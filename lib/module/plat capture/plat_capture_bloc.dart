// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:face_recognition/service/ocr_isolate_pool.dart';
import 'package:face_recognition/service/yolo_isolate_pool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

import 'plat_capture_event.dart';
import 'plat_capture_state.dart';

class PlateCameraCaptureBloc
    extends Bloc<PlateCameraCaptureEvent, PlateCameraCaptureState> {
  final YoloIsolatePool yolo;
  final OcrIsolatePool ocr;

  PlateCameraCaptureBloc({required this.yolo, required this.ocr})
    : super(
        PlateCameraCaptureState(
          isReady: false,
          isProcessing: false,
          progress: 0.0,
          message: "Menyiapkan kamera...",
          lastText: null,
          preview: null,
          controller: null,
        ),
      ) {
    on<InitializeCamera>(_onInit);
    on<CapturePhoto>(_onCapture);
    on<ResetCamera>(_onReset);
  }

  Future<void> _onInit(
    InitializeCamera ev,
    Emitter<PlateCameraCaptureState> emit,
  ) async {
    try {
      final controller = CameraController(
        ev.camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await controller.initialize();

      emit(
        PlateCameraCaptureState(
          isReady: true,
          isProcessing: false,
          progress: 0.0,
          message: "📸 Kamera siap digunakan",
          lastText: null,
          preview: null,
          controller: controller,
        ),
      );
    } catch (e) {
      emit(
        PlateCameraCaptureState(
          isReady: false,
          isProcessing: false,
          progress: 0.0,
          message: "❌ Gagal inisialisasi kamera: $e",
          lastText: null,
          preview: null,
          controller: null,
        ),
      );
    }
  }

  Future<void> _onCapture(
    CapturePhoto ev,
    Emitter<PlateCameraCaptureState> emit,
  ) async {
    final controller = state.controller;
    if (controller == null || !controller.value.isInitialized) return;

    emit(
      PlateCameraCaptureState(
        isReady: true,
        isProcessing: true,
        progress: 0.1,
        message: "📸 Mengambil foto...",
        lastText: null,
        preview: null,
        controller: controller,
      ),
    );

    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final file = await controller.takePicture();
      final bytes = await File(file.path).readAsBytes();

      final img = imglib.decodeImage(bytes);
      if (img == null) throw Exception("Gagal decode foto");

      final fixed = imglib.bakeOrientation(img);
      final fullJpg = Uint8List.fromList(imglib.encodeJpg(fixed, quality: 95));

      emit(
        PlateCameraCaptureState(
          isReady: true,
          isProcessing: true,
          progress: 0.25,
          message: "🔍 Mendeteksi plat...",
          lastText: null,
          preview: fullJpg,
          controller: controller,
        ),
      );

      final detections = await yolo.detect(fullJpg);
      detections.removeWhere((d) => (d.x2 - d.x1) * (d.y2 - d.y1) < 40000);

      if (detections.isEmpty) {
        emit(
          PlateCameraCaptureState(
            isReady: true,
            isProcessing: false,
            progress: 1.0,
            message: "❌ Plat tidak ditemukan",
            lastText: "Tidak terbaca",
            preview: fullJpg,
            controller: controller,
          ),
        );
        return;
      }

      detections.sort((a, b) => b.score.compareTo(a.score));
      final best = detections.first;

      final rect = Rect.fromLTWH(
        best.x1.toDouble(),
        best.y1.toDouble(),
        (best.x2 - best.x1).toDouble(),
        (best.y2 - best.y1).toDouble(),
      );

      final margin = 0.25;
      final mx = rect.width * margin / 2;
      final my = rect.height * margin / 2;
      final expanded = Rect.fromLTRB(
        (rect.left - mx).clamp(0, 640.0),
        (rect.top - my).clamp(0, 640.0),
        (rect.right + mx).clamp(0, 640.0),
        (rect.bottom + my).clamp(0, 640.0),
      );

      final scaleX = fixed.width / 640.0;
      final scaleY = fixed.height / 640.0;
      final scaledRect = Rect.fromLTRB(
        expanded.left * scaleX,
        expanded.top * scaleY,
        expanded.right * scaleX,
        expanded.bottom * scaleY,
      );

      debugPrint(
        "📦 YOLO Box: ${expanded.left.toInt()},${expanded.top.toInt()} → ${expanded.right.toInt()},${expanded.bottom.toInt()}",
      );

      emit(
        PlateCameraCaptureState(
          isReady: true,
          isProcessing: true,
          progress: 0.55,
          message: "✂️ Memotong area plat...",
          lastText: null,
          preview: fullJpg,
          controller: controller,
        ),
      );

      final cropped = await compute(_cropIsolate, {
        'jpeg': fullJpg,
        'rect': scaledRect,
      });
      if (cropped == null) {
        emit(
          PlateCameraCaptureState(
            isReady: true,
            isProcessing: false,
            progress: 1.0,
            message: "❌ Gagal crop gambar",
            lastText: "Tidak terbaca",
            preview: fullJpg,
            controller: controller,
          ),
        );
        return;
      }

      try {
        File(
          '/storage/emulated/0/Download/crop_test.jpg',
        ).writeAsBytesSync(cropped);
        debugPrint("💾 Crop saved to /Download/crop_test.jpg");
      } catch (_) {}

      emit(
        PlateCameraCaptureState(
          isReady: true,
          isProcessing: true,
          progress: 0.75,
          message: "🧠 Memproses OCR...",
          lastText: null,
          preview: cropped,
          controller: controller,
        ),
      );

      String bestText = "";
      final sub = ocr.results.listen((t) {
        if (t.isNotEmpty && t.length > bestText.length) bestText = t;
      });
      ocr.push(cropped);

      final limit = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(limit)) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await sub.cancel();

      final text = bestText.trim();
      emit(
        PlateCameraCaptureState(
          isReady: true,
          isProcessing: false,
          progress: 1.0,
          message: text.isEmpty ? "⚠️ Tidak terbaca" : "✅ Plat: $text",
          lastText: text.isEmpty ? "Tidak terbaca" : text,
          preview: cropped,
          controller: controller,
        ),
      );
    } catch (e, st) {
      debugPrint("❌ Capture error: $e\n$st");
      emit(
        PlateCameraCaptureState(
          isReady: true,
          isProcessing: false,
          progress: 1.0,
          message: "❌ Error: $e",
          lastText: "Error",
          preview: null,
          controller: state.controller,
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
      PlateCameraCaptureState(
        isReady: false,
        isProcessing: false,
        progress: 0.0,
        message: "🔄 Menghidupkan ulang kamera...",
        lastText: null,
        preview: null,
        controller: null,
      ),
    );
    await Future.delayed(const Duration(milliseconds: 300));
    add(InitializeCamera(ev.camera));
  }

  static Uint8List? _cropIsolate(Map<String, dynamic> args) {
    try {
      final jpeg = args['jpeg'] as Uint8List;
      final r = args['rect'] as Rect;
      final img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      final x = r.left.clamp(0, img.width - 1).toInt();
      final y = r.top.clamp(0, img.height - 1).toInt();
      final w = (r.width.clamp(1, img.width - x)).toInt();
      final h = (r.height.clamp(1, img.height - y)).toInt();

      final cropped = imglib.copyCrop(img, x: x, y: y, width: w, height: h);
      return Uint8List.fromList(imglib.encodeJpg(cropped, quality: 95));
    } catch (e) {
      debugPrint("❌ Crop error: $e");
      return null;
    }
  }
}
