// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;
import 'package:vehicle_identification_number/module/plat_capture_mlkit/plat_capture_mlkit_event.dart';
import 'package:vehicle_identification_number/module/plat_capture_mlkit/plat_capture_mlkit_state.dart';
import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';
import 'package:vehicle_identification_number/service/yolo_isolate_pool.dart';
import 'package:vehicle_identification_number/utils/plate_processing.dart';

class PlateMlkitCaptureBloc
    extends Bloc<PlateMlkitCaptureEvent, PlateMlkitCaptureState> {
  final YoloIsolatePool yolo;
  final OcrIsolatePool ocr;

  PlateMlkitCaptureBloc({required this.yolo, required this.ocr})
    : super(PlateMlkitCaptureState.initial()) {
    on<InitializeMlkitCamera>(_onInit);
    on<CaptureMlkitPhoto>(_onCapture);
    on<ResetMlkitCamera>(_onReset);
    on<DisposeMlkitCamera>(_onDispose);
    on<ChangeMlkitFlashMode>(_onFlashModeChanged);
  }

  Future<void> _onInit(
    InitializeMlkitCamera ev,
    Emitter<PlateMlkitCaptureState> emit,
  ) async {
    try {
      await state.controller?.dispose();

      final controller = CameraController(
        ev.camera,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      await _applyFlashMode(controller, state.flashMode);

      emit(
        state.copyWith(
          isReady: true,
          controller: controller,
          preview: null,
          lastText: null,
          progress: 0.0,
          isProcessing: false,
          message: "📸 Kamera siap (ML Kit)",
        ),
      );
    } catch (_) {
      emit(
        PlateMlkitCaptureState.initial().copyWith(
          message: "⚠️ Kamera gagal. Coba ulangi.",
        ),
      );
    }
  }

  Future<void> _onCapture(
    CaptureMlkitPhoto ev,
    Emitter<PlateMlkitCaptureState> emit,
  ) async {
    final controller = state.controller;
    if (controller == null) return;

    emit(
      state.copyWith(
        isProcessing: true,
        progress: 0.1,
        message: "📸 Mengambil foto... (ML Kit)",
      ),
    );

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 150));
      }

      final file = await controller.takePicture();
      final bytes = await File(file.path).readAsBytes();

      final img = imglib.decodeImage(bytes);
      if (img == null) throw Exception("Gagal decode foto");

      final fixed = imglib.bakeOrientation(img);

      final upright = fixed.width > fixed.height
          ? imglib.copyRotate(fixed, angle: 90)
          : fixed;

      final fullJpg = Uint8List.fromList(
        imglib.encodeJpg(upright, quality: 96),
      );

      emit(
        state.copyWith(
          preview: fullJpg,
          progress: 0.25,
          message: "🔍 Deteksi plat...",
        ),
      );

      final detections = await yolo.detect(fullJpg);

      if (detections.isEmpty) {
        emit(
          state.copyWith(
            isProcessing: false,
            progress: 1.0,
            lastText: "Tidak terbaca",
            message: "❌ Plat tidak ditemukan",
          ),
        );
        return;
      }

      detections.sort((a, b) => b.score.compareTo(a.score));
      final best = detections.first;

      final rect = Rect.fromLTRB(
        best.x1.toDouble(),
        best.y1.toDouble(),
        best.x2.toDouble(),
        best.y2.toDouble(),
      );

      emit(state.copyWith(progress: 0.45, message: "✂️ Crop plat..."));

      final cropped = await cropPlateRegion(fullJpg, rect, marginFactor: 0.22);
      if (cropped == null) {
        emit(
          state.copyWith(
            isProcessing: false,
            lastText: "Tidak terbaca",
            message: "❌ Gagal crop",
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          preview: cropped,
          progress: 0.7,
          message: "🧠 OCR (ML Kit)...",
        ),
      );

      final text = await ocr.runMlKit(cropped);

      emit(
        state.copyWith(
          isProcessing: false,
          progress: 1.0,
          lastText: text.isEmpty ? "Tidak terbaca" : text,
          message: text.isEmpty
              ? "⚠️ Plat tidak terbaca"
              : "✅ Plat (ML Kit): $text",
          preview: cropped,
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          isProcessing: false,
          lastText: "Error",
          message: "❌ Error capture ML Kit",
          preview: null,
        ),
      );
    }
  }

  Future<void> _onReset(
    ResetMlkitCamera ev,
    Emitter<PlateMlkitCaptureState> emit,
  ) async {
    await state.controller?.dispose();

    emit(
      PlateMlkitCaptureState.initial().copyWith(
        message: "🔄 Restart kamera...",
        flashMode: state.flashMode,
      ),
    );

    await Future.delayed(const Duration(milliseconds: 300));
    add(InitializeMlkitCamera(ev.camera));
  }

  Future<void> _onDispose(
    DisposeMlkitCamera ev,
    Emitter<PlateMlkitCaptureState> emit,
  ) async {
    try {
      await state.controller?.dispose();
    } catch (_) {}

    emit(
      PlateMlkitCaptureState.initial().copyWith(
        message: "Kamera dihentikan.",
        controller: null,
      ),
    );
  }

  Future<void> _onFlashModeChanged(
    ChangeMlkitFlashMode ev,
    Emitter<PlateMlkitCaptureState> emit,
  ) async {
    await _applyFlashMode(state.controller, ev.mode);
    emit(state.copyWith(flashMode: ev.mode, message: "Flash diubah"));
  }

  Future<void> _applyFlashMode(
    CameraController? controller,
    FlashMode mode,
  ) async {
    if (controller == null) return;
    try {
      await controller.setFlashMode(mode);
    } catch (_) {}
  }
}
