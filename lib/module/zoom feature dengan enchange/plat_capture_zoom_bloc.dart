// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as imglib;
import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';
import 'package:vehicle_identification_number/service/yolo_isolate_pool.dart';
import 'package:vehicle_identification_number/utils/plate_processing.dart';

import 'plat_capture_zoom_event.dart';
import 'plat_capture_zoom_state.dart';

class PlateCameraCaptureZoomBloc
    extends Bloc<PlateCameraCaptureZoomEvent, PlateCameraCaptureZoomState> {
  final YoloIsolatePool yolo;
  final OcrIsolatePool ocr;

  PlateCameraCaptureZoomBloc({required this.yolo, required this.ocr})
    : super(PlateCameraCaptureZoomState.initial()) {
    on<InitializeCamera>(_onInit);
    on<CapturePhoto>(_onCapture);
    on<ResetCamera>(_onReset);
    on<ZoomCamera>(_onZoom);
    on<DisposeCamera>(_onDispose);
  }

  Future<void> _onInit(
    InitializeCamera ev,
    Emitter<PlateCameraCaptureZoomState> emit,
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

      if (Platform.isIOS) {
        try {
          await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
        } catch (_) {}
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
          currentZoom: 1.0,
        ),
      );
    } catch (e) {
      emit(
        PlateCameraCaptureZoomState.initial().copyWith(
          message: '❌ Gagal inisialisasi kamera: $e',
        ),
      );
    }
  }

  Future<void> _onZoom(
    ZoomCamera ev,
    Emitter<PlateCameraCaptureZoomState> emit,
  ) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    final maxZoom = await controller.getMaxZoomLevel();
    final minZoom = await controller.getMinZoomLevel();
    final zoom = ev.level.clamp(minZoom, maxZoom);

    await controller.setZoomLevel(zoom);
    emit(state.copyWith(currentZoom: zoom));
  }

  Future<void> _onCapture(
    CapturePhoto ev,
    Emitter<PlateCameraCaptureZoomState> emit,
  ) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    emit(
      state.copyWith(
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
      final bytes = await File(file.path).readAsBytes();
      var img = imglib.decodeImage(bytes);
      if (img == null) throw Exception("Gagal decode foto");

      img = imglib.bakeOrientation(img);

      final zoomLevel = state.currentZoom;
      img = _applyDigitalZoom(img, zoomLevel);
      img = _enhanceForPlate(img, zoomLevel: zoomLevel);

      final fullJpg = Uint8List.fromList(imglib.encodeJpg(img, quality: 95));

      emit(
        state.copyWith(
          progress: 0.25,
          message: '🔍 Mendeteksi plat...',
          preview: fullJpg,
        ),
      );

      final detections = await yolo.detect(fullJpg);

      final minArea = img.width * img.height * 0.0015;
      detections.removeWhere((d) {
        final area = (d.x2 - d.x1) * (d.y2 - d.y1);
        return area < minArea;
      });

      if (detections.isEmpty) {
        emit(
          state.copyWith(
            isProcessing: false,
            progress: 1.0,
            message: '❌ Plat tidak ditemukan',
            lastText: 'Tidak terbaca',
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
          message: '✂️ Memotong area plat...',
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
            message: '❌ Gagal crop gambar',
            lastText: 'Tidak terbaca',
            preview: fullJpg,
          ),
        );
        return;
      }

      emit(
        state.copyWith(
          progress: 0.75,
          message: '🧠 Memproses OCR...',
          preview: cropped,
        ),
      );

      final text = await waitForOcrResult(
        ocr,
        cropped,
        timeout: const Duration(seconds: 5),
      );

      emit(
        state.copyWith(
          isProcessing: false,
          progress: 1.0,
          message: text.isEmpty ? '⚠️ Tidak terbaca' : '✅ Plat: $text',
          lastText: text.isEmpty ? 'Tidak terbaca' : text,
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
    Emitter<PlateCameraCaptureZoomState> emit,
  ) async {
    final cam = state.controller;
    if (cam != null) {
      try {
        await cam.dispose();
      } catch (_) {}
    }
    emit(
      PlateCameraCaptureZoomState.initial().copyWith(
        message: '🔄 Menghidupkan ulang kamera...',
      ),
    );
    await Future.delayed(const Duration(milliseconds: 300));
    add(InitializeCamera(ev.camera));
  }

  Future<void> _onDispose(
    DisposeCamera ev,
    Emitter<PlateCameraCaptureZoomState> emit,
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
      PlateCameraCaptureZoomState.initial().copyWith(
        message: 'Kamera dihentikan',
        controller: null,
        lastText: null,
        preview: null,
        currentZoom: 1.0,
      ),
    );
  }
}

imglib.Image _applyDigitalZoom(imglib.Image image, double zoomLevel) {
  final effectiveZoom = zoomLevel.clamp(1.0, 6.0);
  if (effectiveZoom <= 1.01) return image;

  final int cropWidth = (image.width / effectiveZoom).round().clamp(
    1,
    image.width,
  );
  final int cropHeight = (image.height / effectiveZoom).round().clamp(
    1,
    image.height,
  );

  final int left = ((image.width - cropWidth) / 2).round().clamp(
    0,
    image.width - 1,
  );
  final int top = ((image.height - cropHeight) / 2).round().clamp(
    0,
    image.height - 1,
  );

  final int remainingWidth = image.width - left;
  final int remainingHeight = image.height - top;

  int safeWidth = cropWidth <= remainingWidth ? cropWidth : remainingWidth;
  int safeHeight = cropHeight <= remainingHeight ? cropHeight : remainingHeight;

  if (safeWidth < 1) safeWidth = 1;
  if (safeHeight < 1) safeHeight = 1;

  final cropped = imglib.copyCrop(
    image,
    x: left,
    y: top,
    width: safeWidth,
    height: safeHeight,
  );

  if (effectiveZoom <= 1.2) return cropped;

  final upscale = math.min(effectiveZoom, 3.0);
  return imglib.copyResize(
    cropped,
    width: (cropped.width * upscale).round(),
    height: (cropped.height * upscale).round(),
    interpolation: imglib.Interpolation.cubic,
  );
}

imglib.Image _enhanceForPlate(imglib.Image image, {double zoomLevel = 1.0}) {
  final contrast = zoomLevel > 2.0 ? 1.4 : 1.25;
  final brightness = zoomLevel > 2.0 ? 0.08 : 0.05;
  final saturation = zoomLevel > 2.0 ? 1.12 : 1.05;

  final adjusted = imglib.adjustColor(
    image,
    contrast: contrast,
    brightness: brightness,
    saturation: saturation,
  );

  if (zoomLevel <= 1.5) return adjusted;

  final double upscale;
  if (zoomLevel > 3.0) {
    upscale = 1.8;
  } else if (zoomLevel > 2.2) {
    upscale = 1.6;
  } else {
    upscale = 1.35;
  }

  final resized = imglib.copyResize(
    adjusted,
    width: (adjusted.width * upscale).round(),
    height: (adjusted.height * upscale).round(),
    interpolation: imglib.Interpolation.cubic,
  );

  return imglib.adjustColor(
    resized,
    contrast: 1.08,
    brightness: 0.0,
    saturation: 1.0,
    gamma: 0.95,
  );
}
