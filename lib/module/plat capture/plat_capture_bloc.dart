// ignore_for_file: depend_on_referenced_packages, dead_code, unnecessary_overrides

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:face_recognition/module/plat%20capture/plat_capture_event.dart';
import 'package:face_recognition/module/plat%20capture/plat_capture_state.dart';
import 'package:face_recognition/service/ocr_isolate_pool.dart';
import 'package:face_recognition/service/yolo_isolate_pool.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

class PlateCaptureBloc extends Bloc<PlateCaptureEvent, PlateCaptureState> {
  final YoloIsolatePool yolo;
  final OcrIsolatePool ocr;

  bool _streamActive = false;
  Uint8List? _lastFrameBytes;
  bool _captureInProgress = false;
  final bool _busy = false;

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
    ResolutionPreset preset = ResolutionPreset.max;

    try {
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        final sdk = android.version.sdkInt;
        if (sdk <= 30) {
          preset = ResolutionPreset.high;
        } else {
          preset = ResolutionPreset.max;
        }
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        final versionString = ios.systemVersion;
        final version = double.tryParse(versionString.split('.').first) ?? 0.0;
        if (version < 15) {
          preset = ResolutionPreset.high;
        } else {
          preset = ResolutionPreset.max;
        }
      }
    } catch (e) {
      preset = ResolutionPreset.high;
    }

    debugPrint('🎥 Using camera preset: $preset');

    final controller = CameraController(
      ev.camera,
      preset,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    _streamActive = true;
    ocr.start();

    controller.startImageStream((img) async {
      if (!_streamActive) return;
      _lastFrameBytes = await _convertToJpg(img);
    });

    emit(
      PlateCaptureState(
        isCameraReady: true,
        controller: controller,
        isProcessing: false,
        lastBox: null,
        lastText: null,
        message: "📷 Kamera siap capture (${preset.name})",
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
    if (_busy || _captureInProgress) return;
    _captureInProgress = true;

    emit(
      PlateCaptureState(
        isCameraReady: true,
        controller: state.controller,
        isProcessing: true,
        lastBox: null,
        lastText: null,
        message: "📸 Memproses gambar...",
      ),
    );

    try {
      final bytes = _lastFrameBytes;
      if (bytes == null) {
        emit(_failed("Tidak ada frame tersedia"));
        _captureInProgress = false;
        return;
      }

      final result = await yolo.detect(bytes);
      if (result.isEmpty) {
        emit(_failed("❌ Tidak ada plat terdeteksi"));
        _captureInProgress = false;
        return;
      }

      result.sort((a, b) => b.score.compareTo(a.score));
      final best = result.first;
      if (best.score < 0.35) {
        emit(
          _failed(
            "Confidence terlalu rendah (${best.score.toStringAsFixed(2)})",
          ),
        );
        _captureInProgress = false;
        return;
      }

      final rect = Rect.fromLTWH(
        best.x1.toDouble(),
        best.y1.toDouble(),
        (best.x2 - best.x1).toDouble(),
        (best.y2 - best.y1).toDouble(),
      );

      final cropped = await _crop(bytes, rect);
      if (cropped == null) {
        emit(_failed("Gagal crop gambar"));
        _captureInProgress = false;
        return;
      }

      ocr.push(cropped);
      String text = "";
      final sub = ocr.results.listen((t) {
        if (t.isNotEmpty && text.isEmpty) text = t;
      });

      final limit = DateTime.now().add(const Duration(seconds: 2));
      while (text.isEmpty && DateTime.now().isBefore(limit)) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await sub.cancel();

      emit(
        PlateCaptureState(
          isCameraReady: true,
          controller: state.controller,
          isProcessing: false,
          lastBox: rect,
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

  PlateCaptureState _failed(String msg) => PlateCaptureState(
    isCameraReady: true,
    controller: state.controller,
    isProcessing: false,
    lastBox: null,
    lastText: "Tidak terbaca",
    message: msg,
  );

  Future<Uint8List?> _convertToJpg(CameraImage img) async {
    try {
      if (Platform.isIOS && img.format.group == ImageFormatGroup.bgra8888) {
        final plane = img.planes.first;
        final image = imglib.Image.fromBytes(
          width: img.width,
          height: img.height,
          bytes: plane.bytes.buffer,
          order: imglib.ChannelOrder.bgra,
        );
        return Uint8List.fromList(imglib.encodeJpg(image, quality: 70));
      } else {
        final image = _yuvToRgb(img);
        return Uint8List.fromList(imglib.encodeJpg(image, quality: 70));
      }
    } catch (_) {
      return null;
    }
  }

  imglib.Image _yuvToRgb(CameraImage img) {
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

  Future<Uint8List?> _crop(Uint8List jpeg, Rect r) async {
    try {
      final img = imglib.decodeImage(jpeg);
      if (img == null) return null;
      final cropped = imglib.copyCrop(
        img,
        x: r.left.round(),
        y: r.top.round(),
        width: r.width.round(),
        height: r.height.round(),
      );
      return Uint8List.fromList(imglib.encodeJpg(cropped, quality: 90));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    return super.close();
  }
}
