// ignore_for_file: invalid_use_of_visible_for_testing_member, depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:face_recognition/module/plat/plat_event.dart';
import 'package:face_recognition/module/plat/plat_state.dart';
import 'package:face_recognition/service/ocr_isolate_pool.dart';
import 'package:face_recognition/service/yolo_isolate_pool.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

class PlateBloc extends Bloc<PlateEvent, PlateState> {
  final YoloIsolatePool yoloPool;
  final OcrIsolatePool ocrPool;

  bool _busy = false;
  bool _streamActive = false;
  bool _captureMode = false;

  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);

  Rect? _smoothBox;

  double _fps = 0;
  DateTime _lastFrame = DateTime.now();
  String _activeResolution = "high";

  final int _yoloIntervalMs = 140;
  final int _ocrIntervalMs = 400;

  StreamSubscription<String>? _ocrLiveSub;

  PlateBloc({required this.yoloPool, required this.ocrPool})
    : super(
        PlateState(
          isCameraReady: false,
          controller: null,
          isProcessing: false,
          lastBox: null,
          lastText: null,
          detectedPlates: [],
          message: null,
          isFromCapture: false,
        ),
      ) {
    on<StartCamera>(_onStartCamera);
    on<StopCamera>(_onStopCamera);
    on<ProcessCameraImage>(_onProcessCameraImage);
    on<CaptureAndProcess>(_onCaptureAndProcess);
    on<ClearLastResult>(_onClearLastResult);

    _ocrLiveSub = ocrPool.results.listen((text) {
      if (_captureMode || !_streamActive) return;
      if (text.isEmpty) return;

      final list = List<String>.from(state.detectedPlates);
      if (!list.contains(text)) list.add(text);

      emit(
        PlateState(
          isCameraReady: true,
          controller: state.controller,
          isProcessing: false,
          lastBox: _smoothBox,
          lastText: text,
          detectedPlates: list,
          message:
              '📸 ${_activeResolution.toUpperCase()} — ${_fps.toStringAsFixed(1)} FPS\nPlat terbaca:\n$text',
          isFromCapture: false,
        ),
      );
    });
  }

  Future<void> _onStartCamera(StartCamera ev, Emitter<PlateState> emit) async {
    try {
      _streamActive = false;
      _captureMode = false;

      if (state.controller != null) {
        final old = state.controller!;
        if (old.value.isStreamingImages) {
          await old.stopImageStream();
        }
        await old.dispose();
      }
    } catch (_) {}

    final deviceInfo = DeviceInfoPlugin();
    ResolutionPreset resolution = ResolutionPreset.high;
    _activeResolution = "high";
    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        if (info.version.sdkInt <= 30) {
          resolution = ResolutionPreset.medium;
          _activeResolution = "medium";
        }
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final model = info.utsname.machine.toLowerCase();
        if (model.contains('iphone13,')) {
          resolution = ResolutionPreset.medium;
          _activeResolution = "medium";
        }
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

    try {
      await controller.initialize();

      if (_streamActive) return;
      _streamActive = true;
      ocrPool.start();

      controller.startImageStream((image) {
        if (!_streamActive) return;
        add(ProcessCameraImage(image, controller));
      });

      emit(
        PlateState(
          isCameraReady: true,
          controller: controller,
          isProcessing: false,
          lastBox: null,
          lastText: null,
          detectedPlates: [],
          message: 'Kamera aktif (${_activeResolution.toUpperCase()})',
          isFromCapture: false,
        ),
      );
    } catch (e) {
      debugPrint("Camera init error: $e");
      emit(
        PlateState(
          isCameraReady: false,
          controller: null,
          isProcessing: false,
          lastBox: null,
          lastText: null,
          detectedPlates: state.detectedPlates,
          message: 'Gagal inisialisasi kamera',
          isFromCapture: false,
        ),
      );
    }
  }

  Future<void> _onStopCamera(StopCamera ev, Emitter<PlateState> emit) async {
    try {
      _streamActive = false;
      _captureMode = false;
      final ctrl = state.controller;
      if (ctrl != null && ctrl.value.isStreamingImages) {
        await ctrl.stopImageStream();
      }
      await ctrl?.dispose();
    } catch (_) {}
    emit(
      PlateState(
        isCameraReady: false,
        controller: null,
        isProcessing: false,
        lastBox: null,
        lastText: null,
        detectedPlates: state.detectedPlates,
        message: 'Kamera berhenti',
        isFromCapture: false,
      ),
    );
  }

  Future<void> _onProcessCameraImage(
    ProcessCameraImage ev,
    Emitter<PlateState> emit,
  ) async {
    final now = DateTime.now();

    final frameDiff = now.difference(_lastFrame).inMilliseconds;
    if (frameDiff > 0) _fps = 1000 / frameDiff;
    _lastFrame = now;

    if (_busy) return;
    if (!_streamActive) return;

    if (now.difference(_lastProcessed).inMilliseconds < _yoloIntervalMs) {
      return;
    }
    _busy = true;
    _lastProcessed = now;

    try {
      final rgbBytes = await _convertToRgbBytes(ev.cameraImage);
      if (rgbBytes == null) return;

      final results = await yoloPool.detect(rgbBytes);
      if (results.isEmpty) return;

      results.sort((a, b) => b.score.compareTo(a.score));
      final top = results.first;
      if (top.score < 0.45) return;

      final rect = Rect.fromLTWH(
        top.x1.toDouble(),
        top.y1.toDouble(),
        (top.x2 - top.x1).toDouble(),
        (top.y2 - top.y1).toDouble(),
      );

      _smoothBox = _applySmoothing(rect, _smoothBox);

      emit(
        PlateState(
          isCameraReady: true,
          controller: ev.controller,
          isProcessing: true,
          lastBox: _smoothBox,
          lastText: state.lastText,
          detectedPlates: state.detectedPlates,
          message:
              '📸 ${_activeResolution.toUpperCase()} — ${_fps.toStringAsFixed(1)} FPS',
          isFromCapture: false,
        ),
      );

      if (now.difference(_lastOcr).inMilliseconds > _ocrIntervalMs) {
        _lastOcr = now;
        final cropped = await _cropRegion(rgbBytes, rect, 640);
        if (cropped != null) ocrPool.push(cropped);
      }
    } finally {
      _busy = false;
    }
  }

  Future<void> _onCaptureAndProcess(
    CaptureAndProcess ev,
    Emitter<PlateState> emit,
  ) async {
    try {
      _streamActive = false;
      _captureMode = true;

      if (state.controller != null) {
        final old = state.controller!;
        if (old.value.isStreamingImages) {
          await old.stopImageStream();
        }
        await old.dispose();
      }
    } catch (_) {}

    final deviceInfo = DeviceInfoPlugin();
    ResolutionPreset resolution = ResolutionPreset.ultraHigh;
    _activeResolution = "ultraHigh";

    try {
      if (Platform.isAndroid) {
        final info = await deviceInfo.androidInfo;
        if (info.version.sdkInt <= 30) {
          resolution = ResolutionPreset.high;
          _activeResolution = "high";
        }
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final model = info.utsname.machine.toLowerCase();
        if (model.contains('iphone13,')) {
          resolution = ResolutionPreset.high;
          _activeResolution = "high";
        }
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

    try {
      await controller.initialize();

      emit(
        PlateState(
          isCameraReady: true,
          controller: null,
          isProcessing: true,
          lastBox: null,
          lastText: null,
          detectedPlates: state.detectedPlates,
          message: '🕓 Mohon tunggu, gambar sedang diproses...',
          isFromCapture: true,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 80));
      final file = await controller.takePicture();
      final bytes = await File(file.path).readAsBytes();

      final results = await yoloPool.detect(bytes);
      if (results.isEmpty) {
        emit(
          PlateState(
            isCameraReady: false,
            controller: null,
            isProcessing: false,
            lastBox: null,
            lastText: "Tidak terbaca",
            detectedPlates: state.detectedPlates,
            message: 'Tidak ada plat terdeteksi ❌',
            isFromCapture: true,
          ),
        );
        await controller.dispose();
        _captureMode = false;
        return;
      }

      results.sort((a, b) => b.score.compareTo(a.score));
      final top = results.first;

      final rect = Rect.fromLTWH(
        top.x1.toDouble(),
        top.y1.toDouble(),
        (top.x2 - top.x1).toDouble(),
        (top.y2 - top.y1).toDouble(),
      );

      final cropped = await _cropRegion(bytes, rect, 640);

      String text = "Tidak terbaca";
      if (cropped != null) {
        final completer = Completer<String>();
        final sub = ocrPool.results.listen((t) {
          if (!completer.isCompleted) completer.complete(t);
        });

        ocrPool.start();
        ocrPool.push(cropped);

        try {
          text = await completer.future.timeout(
            const Duration(seconds: 6),
            onTimeout: () => "Tidak terbaca",
          );
        } finally {
          await sub.cancel();
        }
      }

      emit(
        PlateState(
          isCameraReady: false,
          controller: null,
          isProcessing: false,
          lastBox: rect,
          lastText: text,
          detectedPlates: [...state.detectedPlates, text],
          message: '✅ Capture selesai\nPlat terbaca:\n$text',
          isFromCapture: true,
        ),
      );

      await controller.dispose();
    } catch (e, st) {
      debugPrint("❌ Capture error: $e\n$st");
      emit(
        PlateState(
          isCameraReady: false,
          controller: null,
          isProcessing: false,
          lastBox: null,
          lastText: "Tidak terbaca",
          detectedPlates: state.detectedPlates,
          message: 'Gagal memproses capture 😔',
          isFromCapture: true,
        ),
      );
    } finally {
      _captureMode = false;
      _streamActive = false;
      try {
        if (ev.camera != null) {
          await Future.delayed(const Duration(milliseconds: 300));
          add(StartCamera(ev.camera));
        }
      } catch (e) {
        debugPrint("Restart stream after capture failed: $e");
      }
    }
  }

  void _onClearLastResult(ClearLastResult ev, Emitter<PlateState> emit) {
    emit(
      PlateState(
        isCameraReady: state.isCameraReady,
        controller: state.controller,
        isProcessing: state.isProcessing,
        lastBox: state.lastBox,
        lastText: null,
        detectedPlates: state.detectedPlates,
        message: state.message,
        isFromCapture: state.isFromCapture,
      ),
    );
  }

  Future<Uint8List?> _convertToRgbBytes(CameraImage image) async {
    try {
      if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
        final plane = image.planes.first;
        final img = imglib.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: plane.bytes.buffer,
          order: imglib.ChannelOrder.bgra,
        );
        return Uint8List.fromList(imglib.encodeJpg(img, quality: 70));
      } else {
        final img = _convertYUV420toImageColor(image);
        return Uint8List.fromList(imglib.encodeJpg(img, quality: 70));
      }
    } catch (_) {
      return null;
    }
  }

  imglib.Image _convertYUV420toImageColor(CameraImage image) {
    final width = image.width;
    final height = image.height;
    final img = imglib.Image(width: width, height: height);
    final Y = image.planes[0].bytes;
    final U = image.planes[1].bytes;
    final V = image.planes[2].bytes;
    final uvRowStride = image.planes[1].bytesPerRow;
    final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final yp = Y[y * width + x];
        final up = U[uvIndex];
        final vp = V[uvIndex];

        int r = (yp + vp * 1436 / 1024 - 179).clamp(0, 255).toInt();
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .clamp(0, 255)
            .toInt();
        int b = (yp + up * 1814 / 1024 - 227).clamp(0, 255).toInt();

        img.setPixelRgb(x, y, r, g, b);
      }
    }

    return imglib.copyRotate(img, angle: 90);
  }

  Future<Uint8List?> _cropRegion(
    Uint8List jpeg,
    Rect rect,
    int inputSize,
  ) async {
    try {
      final img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      final sx = img.width / inputSize;
      final sy = img.height / inputSize;

      int x1 = (rect.left * sx).round().clamp(0, img.width - 1);
      int y1 = (rect.top * sy).round().clamp(0, img.height - 1);
      int w = (rect.width * sx).round().clamp(1, img.width - x1);
      int h = (rect.height * sy).round().clamp(1, img.height - y1);

      final cropped = imglib.copyCrop(img, x: x1, y: y1, width: w, height: h);
      return Uint8List.fromList(imglib.encodeJpg(cropped, quality: 90));
    } catch (_) {
      return null;
    }
  }

  Rect _applySmoothing(Rect newBox, Rect? prevBox, {double alpha = 0.25}) {
    if (prevBox == null) return newBox;
    double lerp(double a, double b) => a + (b - a) * alpha;
    return Rect.fromLTWH(
      lerp(prevBox.left, newBox.left),
      lerp(prevBox.top, newBox.top),
      lerp(prevBox.width, newBox.width),
      lerp(prevBox.height, newBox.height),
    );
  }

  @override
  Future<void> close() async {
    await _ocrLiveSub?.cancel();
    return super.close();
  }
}
