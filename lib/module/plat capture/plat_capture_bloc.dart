// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';
import 'package:vehicle_identification_number/service/yolo_isolate_pool.dart';
import 'package:vehicle_identification_number/utils/plate_processing.dart';

import 'plat_capture_constants.dart';
import 'plat_capture_event.dart';
import 'plat_capture_state.dart';

class PlateCameraCaptureBloc
    extends Bloc<PlateCameraCaptureEvent, PlateCameraCaptureState> {
  final YoloIsolatePool yolo;
  final OcrIsolatePool ocr;

  PlateCameraCaptureBloc({required this.yolo, required this.ocr})
    : super(PlateCameraCaptureState.initial()) {
    on<InitializeCamera>(_onInit);
    on<CapturePhoto>(_onCapture);
    on<ResetCamera>(_onReset);
    on<DisposeCamera>(_onDispose);
    on<ChangeCaptureFlashMode>(_onFlashModeChanged);
  }

  Future<void> _onInit(
    InitializeCamera ev,
    Emitter<PlateCameraCaptureState> emit,
  ) async {
    try {
      await state.controller?.dispose();

      final controller = CameraController(
        ev.camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();

      await _applyFlashMode(controller, state.flashMode);

      if (Platform.isIOS) {
        try {
          await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        } catch (e) {
          debugPrint('⚠️ [Capture] lock orientation failed: $e');
        }
      }

      emit(
        state.copyWith(
          isReady: true,
          isProcessing: false,
          progress: 0.0,
          message: '📸 Kamera siap digunakan',
          lastText: null,
          preview: null,
          controller: controller,
          flashMode: state.flashMode,
        ),
      );
    } catch (e) {
      emit(
        PlateCameraCaptureState.initial().copyWith(
          message:
              'Tunggu beberapa saat, jika masih tidak bisa kembali ke page sebelumnya dan buka kembali page capture ini',
        ),
      );
    }
  }

  Future<void> _onCapture(
    CapturePhoto ev,
    Emitter<PlateCameraCaptureState> emit,
  ) async {
    final controller = state.controller;
    final desiredFlashMode = state.flashMode;
    if (controller == null || !controller.value.isInitialized) return;

    emit(
      state.copyWith(
        isReady: true,
        isProcessing: true,
        progress: 0.1,
        message: '📸 Mengambil foto...',
        lastText: null,
        preview: null,
      ),
    );

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final file = await controller.takePicture();

      // Beberapa perangkat mematikan flash setelah takePicture(); pastikan
      // mode sebelumnya diterapkan lagi agar lampu tetap menyala saat pengguna
      // ingin mengambil ulang foto.
      await _applyFlashMode(controller, desiredFlashMode);
      final bytes = await File(file.path).readAsBytes();

      final img = imglib.decodeImage(bytes);
      if (img == null) throw Exception("Gagal decode foto");

      final fixed = imglib.bakeOrientation(img);

      final imglib.Image upright = fixed.width >= fixed.height
          ? imglib.copyRotate(fixed, angle: 90)
          : fixed;

      final fullJpg = Uint8List.fromList(
        imglib.encodeJpg(upright, quality: 100),
      );

      emit(
        state.copyWith(
          isProcessing: true,
          progress: 0.25,
          message: '🔍 Mendeteksi plat kendaraan...',
          preview: fullJpg,
        ),
      );

      final detections = await yolo.detect(fullJpg);

      final minArea = upright.width * upright.height * 0.0009;
      detections.removeWhere((d) {
        final area = (d.x2 - d.x1) * (d.y2 - d.y1);
        return area < minArea;
      });

      if (detections.isEmpty) {
        emit(
          state.copyWith(
            isProcessing: false,
            progress: 1.0,
            message:
                '❌ Plat tidak terdeteksi, pastikan posisi dan pencahayaan sudah pas',
            lastText: null,
            preview: fullJpg,
          ),
        );
        return;
      }

      detections.sort((a, b) => b.score.compareTo(a.score));
      final best = detections.first;

      final detectionRect = Rect.fromLTRB(
        best.x1.toDouble(),
        best.y1.toDouble(),
        best.x2.toDouble(),
        best.y2.toDouble(),
      );
      emit(
        state.copyWith(
          progress: 0.55,
          message: '✂️ Memotong area plat kendaraan...',
          preview: fullJpg,
        ),
      );

      final cropped = await cropPlateRegion(
        fullJpg,
        detectionRect,
        marginFactor: 0.3,
      );
      if (cropped == null) {
        emit(
          state.copyWith(
            isProcessing: false,
            progress: 1.0,
            message: '❌ Plat tidak terdeteksi, coba ambil ulang',
            lastText: null,
            preview: fullJpg,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          progress: 0.75,
          message: '🧠 Memproses...',
          preview: cropped,
        ),
      );

      var text = await waitForOcrResult(
        ocr,
        cropped,
        timeout: const Duration(seconds: 5),
      );

      if (text.isEmpty || text.length < 5) {
        final broadAttempt = await waitForOcrResult(
          ocr,
          fullJpg,
          timeout: const Duration(seconds: 6),
        );
        if (broadAttempt.isNotEmpty) {
          text = broadAttempt;
        }
      }
      emit(
        state.copyWith(
          isProcessing: false,
          progress: 1.0,
          message: text.isEmpty
              ? '⚠️ Plat Tidak terbaca, coba ubah angle\natau cari pencahayaan yang baik'
              : '✅ Plat: $text',
          lastText: text.isEmpty ? fallbackText : text,
          preview: cropped,
        ),
      );
    } catch (e, st) {
      debugPrint("❌ Capture error: $e\n$st");
      emit(
        state.copyWith(
          isProcessing: false,
          progress: 1.0,
          message: '❌ Error: $e',
          lastText: 'Error',
          preview: null,
        ),
      );
    }
  }

  Future<void> _onReset(
    ResetCamera ev,
    Emitter<PlateCameraCaptureState> emit,
  ) async {
    final cam = state.controller;
    if (cam != null) {
      try {
        await cam.dispose();
      } catch (_) {}
    }
    emit(
      PlateCameraCaptureState.initial().copyWith(
        message: '🔄 Menghidupkan ulang kamera...',
        flashMode: state.flashMode,
      ),
    );
    await Future.delayed(const Duration(milliseconds: 300));
    add(InitializeCamera(ev.camera));
  }

  Future<void> _onDispose(
    DisposeCamera ev,
    Emitter<PlateCameraCaptureState> emit,
  ) async {
    final controller = state.controller;
    if (controller != null) {
      try {
        if (controller.value.isStreamingImages) {
          await controller.stopImageStream();
        }
      } catch (_) {}
      try {
        await controller.dispose();
      } catch (_) {}
    }

    emit(
      PlateCameraCaptureState.initial().copyWith(
        message: 'Kamera dihentikan',
        controller: null,
        lastText: null,
        preview: null,
        flashMode: state.flashMode,
      ),
    );
  }

  Future<void> _onFlashModeChanged(
    ChangeCaptureFlashMode ev,
    Emitter<PlateCameraCaptureState> emit,
  ) async {
    await _applyFlashMode(state.controller, ev.mode);

    final label = switch (ev.mode) {
      FlashMode.auto => 'Auto',
      FlashMode.torch => 'Nyala',
      _ => 'Mati',
    };

    emit(
      state.copyWith(
        flashMode: ev.mode,
        message: '🔦 Flash $label',
      ),
    );
  }

  Future<void> _applyFlashMode(
    CameraController? controller,
    FlashMode mode,
  ) async {
    if (controller == null) return;
    try {
      await controller.setFlashMode(mode);
    } catch (e) {
      debugPrint('⚠️ [Capture] gagal set flash: $e');
    }
  }
}
