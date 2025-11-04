// ignore_for_file: dead_code, depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:face_recognition/module/plat%20realtime/plat_realtime_event.dart';
import 'package:face_recognition/module/plat%20realtime/plat_realtime_state.dart';
import 'package:face_recognition/service/ocr_isolate_pool.dart';
import 'package:face_recognition/service/yolo_isolate_pool.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

class PlateRealtimeBloc extends Bloc<PlateRealtimeEvent, PlateRealtimeState> {
  final YoloIsolatePool yoloPool;
  final OcrIsolatePool ocrPool;

  bool _busy = false;
  bool _streamActive = false;
  double _fps = 0;
  DateTime _lastFrame = DateTime.now();
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
  Rect? _smoothBox;
  String activeResolution = "veryHigh";
  final int _intervalYolo = 150;
  final int _intervalOcr = 400;

  StreamSubscription<String>? _ocrSub;

  PlateRealtimeBloc({required this.yoloPool, required this.ocrPool})
    : super(
        PlateRealtimeState(
          isCameraReady: false,
          controller: null,
          isProcessing: false,
          lastBox: null,
          lastText: null,
          detected: [],
          message: null,
        ),
      ) {
    on<StartRealtimeCamera>(_onStartCamera);
    on<StopRealtimeCamera>(_onStopCamera);
    on<RealtimeFrameArrived>(_onFrameArrived);

    _ocrSub = ocrPool.results.listen((text) {
      if (!_streamActive || text.isEmpty) return;
      final updated = List<String>.from(state.detected);
      if (!updated.contains(text)) updated.add(text);
      emit(
        PlateRealtimeState(
          isCameraReady: true,
          controller: state.controller,
          isProcessing: false,
          lastBox: _smoothBox,
          lastText: text,
          detected: updated,
          message: '✅ Plat: $text',
        ),
      );
    });
  }

  Future<void> _onStartCamera(
    StartRealtimeCamera ev,
    Emitter<PlateRealtimeState> emit,
  ) async {
    final deviceInfo = DeviceInfoPlugin();
    ResolutionPreset resolution = ResolutionPreset.veryHigh;
    activeResolution = "veryHigh";
    try {
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        final sdk = android.version.sdkInt;
        if (sdk <= 30) {
          resolution = ResolutionPreset.medium;
        } else {
          resolution = ResolutionPreset.veryHigh;
        }
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final model = info.utsname.machine.toLowerCase();

        if (model.contains('iphone13,')) {
          resolution = ResolutionPreset.medium;
          activeResolution = "medium";
        } else {
          resolution = ResolutionPreset.veryHigh;
          activeResolution = "veryHigh";
        }
        debugPrint(
          "📱 iPhone model: ${info.utsname.machine} → Resolution: ${resolution.name}",
        );
      }
    } catch (e) {
      resolution = ResolutionPreset.veryHigh;
    }

    debugPrint('🎥 [Realtime] Using camera preset: $resolution');

    final controller = CameraController(
      ev.camera,
      resolution,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    _streamActive = true;
    ocrPool.start();

    controller.startImageStream((img) {
      if (!_streamActive) return;
      add(RealtimeFrameArrived(img, controller));
    });

    emit(
      PlateRealtimeState(
        isCameraReady: true,
        controller: controller,
        isProcessing: false,
        lastBox: null,
        lastText: null,
        detected: [],
        message: "📸 Kamera aktif (${resolution.name})",
      ),
    );
  }

  Future<void> _onStopCamera(
    StopRealtimeCamera ev,
    Emitter<PlateRealtimeState> emit,
  ) async {
    _streamActive = false;
    try {
      await state.controller?.stopImageStream();
      await state.controller?.dispose();
    } catch (_) {}
    emit(
      PlateRealtimeState(
        isCameraReady: false,
        controller: null,
        isProcessing: false,
        lastBox: null,
        lastText: null,
        detected: state.detected,
        message: "Kamera berhenti",
      ),
    );
  }

  Future<void> _onFrameArrived(
    RealtimeFrameArrived ev,
    Emitter<PlateRealtimeState> emit,
  ) async {
    final now = DateTime.now();
    if (_busy) return;
    final diff = now.difference(_lastFrame).inMilliseconds;
    if (diff > 0) _fps = 1000 / diff;
    _lastFrame = now;

    if (now.difference(_lastProcessed).inMilliseconds < _intervalYolo) return;
    _busy = true;
    _lastProcessed = now;

    try {
      final bytes = await _toRGB(ev.image);
      if (bytes == null) return;
      final result = await yoloPool.detect(bytes);
      if (result.isEmpty) return;

      result.sort((a, b) => b.score.compareTo(a.score));
      final best = result.first;
      if (best.score < 0.4) return;

      final rect = Rect.fromLTWH(
        best.x1.toDouble(),
        best.y1.toDouble(),
        (best.x2 - best.x1).toDouble(),
        (best.y2 - best.y1).toDouble(),
      );
      _smoothBox = _blend(rect, _smoothBox);

      if (now.difference(_lastOcr).inMilliseconds > _intervalOcr) {
        _lastOcr = now;
        final crop = await _crop(bytes, rect);
        if (crop != null) ocrPool.push(crop);
      }

      emit(
        PlateRealtimeState(
          isCameraReady: true,
          controller: ev.controller,
          isProcessing: false,
          lastBox: _smoothBox,
          lastText: state.lastText,
          detected: state.detected,
          message:
              "⚙️ FPS: ${_fps.toStringAsFixed(1)} | Plat: ${state.lastText ?? '-'}",
        ),
      );
    } finally {
      _busy = false;
    }
  }

  Future<Uint8List?> _toRGB(CameraImage img) async {
    try {
      if (Platform.isIOS && img.format.group == ImageFormatGroup.bgra8888) {
        final p = img.planes.first;
        final image = imglib.Image.fromBytes(
          width: img.width,
          height: img.height,
          bytes: p.bytes.buffer,
          order: imglib.ChannelOrder.bgra,
        );
        return Uint8List.fromList(imglib.encodeJpg(image, quality: 50));
      } else {
        final i = _yuvToRgb(img);
        return Uint8List.fromList(imglib.encodeJpg(i, quality: 50));
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
    final uvRowStride = img.planes[1].bytesPerRow;
    final uvPixelStride = img.planes[1].bytesPerPixel ?? 1;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
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

  Future<Uint8List?> _crop(Uint8List jpeg, Rect rect) async {
    final img = imglib.decodeImage(jpeg);
    if (img == null) return null;
    final cropped = imglib.copyCrop(
      img,
      x: rect.left.toInt(),
      y: rect.top.toInt(),
      width: rect.width.toInt(),
      height: rect.height.toInt(),
    );
    return Uint8List.fromList(imglib.encodeJpg(cropped, quality: 90));
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
    await _ocrSub?.cancel();
    return super.close();
  }
}
