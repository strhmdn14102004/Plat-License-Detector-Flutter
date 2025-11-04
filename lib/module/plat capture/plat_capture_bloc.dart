// ignore_for_file: unnecessary_overrides, depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:face_recognition/module/plat%20capture/plat_capture_event.dart';
import 'package:face_recognition/module/plat%20capture/plat_capture_state.dart';
import 'package:face_recognition/service/ocr_isolate_pool.dart';
import 'package:face_recognition/service/yolo_isolate_pool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

class PlateCaptureBloc extends Bloc<PlateCaptureEvent, PlateCaptureState> {
  final YoloIsolatePool yolo;
  final OcrIsolatePool ocr;

  bool _streamActive = false;
  Uint8List? _lastFrameBytes;
  bool _captureInProgress = false;
  String activeResolution = "high";
  Rect? _lastBox;

  PlateCaptureBloc({required this.yolo, required this.ocr})
    : super(
        PlateCaptureState(
          isCameraReady: false,
          controller: null,
          isProcessing: false,
          lastBox: null,
          lastText: null,
          message: null,
        ),
      ) {
    on<StartCaptureCamera>(_onStart);
    on<StopCaptureCamera>(_onStop);
    on<CaptureAndProcessFrame>(_onCapture);
  }

  Future<void> _onStart(
    StartCaptureCamera ev,
    Emitter<PlateCaptureState> emit,
  ) async {
    final info = DeviceInfoPlugin();
    final deviceInfo = DeviceInfoPlugin();
    ResolutionPreset resolution = ResolutionPreset.high;
    activeResolution = "high";

    try {
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final sdk = android.version.sdkInt;
        resolution = sdk <= 30
            ? ResolutionPreset.medium
            : ResolutionPreset.high;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final model = info.utsname.machine.toLowerCase();

        if (model.contains('iphone13,')) {
          resolution = ResolutionPreset.medium;
          activeResolution = "medium";
        } else {
          resolution = ResolutionPreset.high;
          activeResolution = "high";
        }
        debugPrint(
          "📱 iPhone model: ${info.utsname.machine} → Resolution: ${resolution.name}",
        );
      }
    } catch (_) {}

    final controller = CameraController(
      ev.camera,
      resolution,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    await controller.setFocusMode(FocusMode.auto);
    await controller.setExposureMode(ExposureMode.auto);
    await controller.lockCaptureOrientation();
    await controller.setFocusPoint(null);

    _streamActive = true;
    ocr.start();

    controller.startImageStream((img) async {
      if (!_streamActive) return;

      _lastFrameBytes = await compute(_convertToJpgIsolate, img);
    });

    emit(
      PlateCaptureState(
        isCameraReady: true,
        controller: controller,
        isProcessing: false,
        lastBox: null,
        lastText: null,
        message: "📷 Kamera siap capture (${resolution.name})",
      ),
    );
  }

  Future<void> _onStop(
    StopCaptureCamera ev,
    Emitter<PlateCaptureState> emit,
  ) async {
    _streamActive = false;
    try {
      await state.controller?.stopImageStream();
      await state.controller?.dispose();
    } catch (_) {}
    emit(
      PlateCaptureState(
        isCameraReady: false,
        controller: null,
        isProcessing: false,
        lastBox: null,
        lastText: null,
        message: "Kamera berhenti",
      ),
    );
  }

  Future<void> _onCapture(
    CaptureAndProcessFrame ev,
    Emitter<PlateCaptureState> emit,
  ) async {
    if (_captureInProgress) return;
    _captureInProgress = true;

    emit(
      PlateCaptureState(
        isCameraReady: true,
        controller: state.controller,
        isProcessing: true,
        lastBox: null,
        lastText: null,
        message: "🔍 Mencari plat kendaraan...",
      ),
    );

    try {
      try {
        await state.controller?.setFocusMode(FocusMode.auto);
        await Future.delayed(const Duration(milliseconds: 350));
      } catch (_) {}

      Uint8List? frame = _lastFrameBytes;
      if (frame == null) {
        emit(_failed("❌ Tidak ada frame tersedia"));
        _captureInProgress = false;
        return;
      }

      await Future.delayed(const Duration(milliseconds: 60));

      List<YoloResult> result = [];
      for (int i = 0; i < 3; i++) {
        result = await yolo.detect(frame);
        if (result.isNotEmpty && result.first.score > 0.45) break;
        await Future.delayed(const Duration(milliseconds: 250));
      }

      if (result.isEmpty) {
        emit(_failed("❌ Plat tidak terdeteksi (YOLO gagal)"));
        _captureInProgress = false;
        return;
      }

      result.sort((a, b) => b.score.compareTo(a.score));
      final best = result.first;
      final rect = Rect.fromLTWH(
        best.x1.toDouble(),
        best.y1.toDouble(),
        (best.x2 - best.x1).toDouble(),
        (best.y2 - best.y1).toDouble(),
      );
      _lastBox = _blend(rect, _lastBox);

      final cropped = await compute(_cropIsolate, {
        'jpeg': frame,
        'rect': _lastBox!,
      });
      if (cropped == null) {
        emit(_failed("❌ Gagal crop gambar"));
        _captureInProgress = false;
        return;
      }

      emit(
        PlateCaptureState(
          isCameraReady: true,
          controller: state.controller,
          isProcessing: true,
          lastBox: _lastBox,
          lastText: null,
          message: "🧠 Memproses OCR (akurat, mohon tunggu)...",
        ),
      );

      String bestText = "";
      final sub = ocr.results.listen((t) {
        if (t.isNotEmpty && t.length > bestText.length) bestText = t;
      });

      ocr.push(cropped);
      final limit = DateTime.now().add(const Duration(seconds: 6));
      while (DateTime.now().isBefore(limit)) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await sub.cancel();

      final text = bestText.trim();

      emit(
        PlateCaptureState(
          isCameraReady: true,
          controller: state.controller,
          isProcessing: false,
          lastBox: _lastBox,
          lastText: text.isEmpty ? "Tidak terbaca" : text,
          message: text.isEmpty ? "⚠️ Tidak terbaca" : "✅ Plat: $text",
        ),
      );
    } catch (e) {
      emit(_failed("❌ Error: $e"));
    } finally {
      _captureInProgress = false;
    }
  }

  PlateCaptureState _failed(String msg) {
    return PlateCaptureState(
      isCameraReady: true,
      controller: state.controller,
      isProcessing: false,
      lastBox: null,
      lastText: "Tidak terbaca",
      message: msg,
    );
  }

  static Future<Uint8List?> _convertToJpgIsolate(CameraImage img) async {
    try {
      late imglib.Image image;
      if (Platform.isIOS && img.format.group == ImageFormatGroup.bgra8888) {
        final plane = img.planes.first;
        image = imglib.Image.fromBytes(
          width: img.width,
          height: img.height,
          bytes: plane.bytes.buffer,
          order: imglib.ChannelOrder.bgra,
        );
      } else {
        image = _yuvToRgb(img);
      }

      final enhanced = imglib.adjustColor(
        image,
        contrast: 1.1,
        saturation: 1.05,
      );
      final sharpened = imglib.convolution(
        enhanced,
        filter: [0, -1, 0, -1, 5, -1, 0, -1, 0],
      );
      return Uint8List.fromList(imglib.encodeJpg(sharpened, quality: 95));
    } catch (_) {
      return null;
    }
  }

  static imglib.Image _yuvToRgb(CameraImage img) {
    final w = img.width;
    final h = img.height;
    final out = imglib.Image(width: w, height: h);
    final Y = img.planes[0].bytes;
    final U = img.planes[1].bytes;
    final V = img.planes[2].bytes;
    final uvRow = img.planes[1].bytesPerRow;
    final uvPix = img.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final uvIndex = uvPix * (x ~/ 2) + uvRow * (y ~/ 2);
        final yp = Y[y * w + x];
        final up = U[uvIndex];
        final vp = V[uvIndex];
        int r = (yp + vp * 1436 / 1024 - 179).clamp(0, 255).toInt();
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .clamp(0, 255)
            .toInt();
        int b = (yp + up * 1814 / 1024 - 227).clamp(0, 255).toInt();
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return imglib.copyRotate(out, angle: 90);
  }

  static Uint8List? _cropIsolate(Map<String, dynamic> args) {
    final jpeg = args['jpeg'] as Uint8List;
    final r = args['rect'] as Rect;
    try {
      final img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      final marginX = (r.width * 0.2).round();
      final marginY = (r.height * 0.15).round();
      final x = (r.left - marginX).clamp(0, img.width - 1).toInt();
      final y = (r.top - marginY).clamp(0, img.height - 1).toInt();
      final w = ((r.width + marginX * 2).clamp(0, img.width - x)).toInt();
      final h = ((r.height + marginY * 2).clamp(0, img.height - y)).toInt();

      final cropped = imglib.copyCrop(img, x: x, y: y, width: w, height: h);
      return Uint8List.fromList(imglib.encodeJpg(cropped, quality: 95));
    } catch (_) {
      return null;
    }
  }

  Rect _blend(Rect n, Rect? p, {double a = 0.3}) {
    if (p == null) return n;
    double lerp(double x, double y) => x + (y - x) * a;
    return Rect.fromLTWH(
      lerp(p.left, n.left),
      lerp(p.top, n.top),
      lerp(p.width, n.width),
      lerp(p.height, n.height),
    );
  }

  @override
  Future<void> close() async {
    return super.close();
  }
}
