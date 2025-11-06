import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:face_recognition/module/plat realtime/plat_realtime_event.dart';
import 'package:face_recognition/module/plat realtime/plat_realtime_state.dart';
import 'package:face_recognition/service/ocr_isolate_pool.dart';
import 'package:face_recognition/service/yolo_isolate_pool.dart';
import 'package:face_recognition/utils/plate_processing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  String activeResolution = "high";
  int _sensorOrientation = 90;
  CameraLensDirection? _lensDirection;
  Size? _lastFrameSize;

  final int _intervalYolo = 200;
  final int _intervalOcr = 600;

  StreamSubscription<String>? _ocrSub;

  PlateRealtimeBloc({required this.yoloPool, required this.ocrPool})
    : super(PlateRealtimeState.initial()) {
    on<StartRealtimeCamera>(_onStartCamera);
    on<StopRealtimeCamera>(_onStopCamera);
    on<RealtimeFrameArrived>(_onFrameArrived);

    _ocrSub = ocrPool.results.listen((text) {
      if (!_streamActive || text.isEmpty) return;
      final updated = List<String>.from(state.detected);
      if (!updated.contains(text)) updated.add(text);
      emit(
        state.copyWith(
          isCameraReady: true,
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
    ResolutionPreset resolution = ResolutionPreset.high;
    activeResolution = "high";

    try {
      if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        final sdk = android.version.sdkInt;
        resolution = sdk <= 30
            ? ResolutionPreset.medium
            : ResolutionPreset.high;
        activeResolution = resolution.name;
      } else if (Platform.isIOS) {
        final info = await deviceInfo.iosInfo;
        final model = info.utsname.machine.toLowerCase();

        if (model.contains('iphone10,') ||
            model.contains('iphone11,') ||
            model.contains('iphone12,1')) {
          resolution = ResolutionPreset.high;
          activeResolution = "high";
        } else {
          resolution = ResolutionPreset.veryHigh;
          activeResolution = "veryHigh";
        }

        debugPrint(
          "📱 iPhone model: ${info.utsname.machine} → Resolution: ${resolution.name}",
        );
      }
    } catch (e) {
      resolution = ResolutionPreset.high;
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

    _sensorOrientation = controller.description.sensorOrientation;
    _lensDirection = controller.description.lensDirection;
    _smoothBox = null;
    _lastFrameSize = null;

    if (Platform.isIOS) {
      await controller.lockCaptureOrientation(DeviceOrientation.portraitUp);
    }

    _streamActive = true;
    ocrPool.start();

    controller.startImageStream((img) {
      if (!_streamActive) return;
      add(RealtimeFrameArrived(img, controller));
    });

    emit(
      state.copyWith(
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

    _smoothBox = null;
    _lensDirection = null;
    _lastFrameSize = null;

    emit(
      state.copyWith(
        isCameraReady: false,
        controller: null,
        isProcessing: false,
        lastBox: null,
        lastText: null,
        message: 'Kamera berhenti',
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

      final frameSize = _lastFrameSize;
      if (frameSize != null) {
        final double minArea =
            frameSize.width * frameSize.height * 0.0012; // ~0.12%
        result.removeWhere((d) {
          final area = (d.x2 - d.x1) * (d.y2 - d.y1);
          return area < minArea;
        });
      }

      result.sort((a, b) => b.score.compareTo(a.score));
      final best = result.first;
      if (best.score < 0.4) return;

      final rawRect = Rect.fromLTRB(
        best.x1.toDouble(),
        best.y1.toDouble(),
        best.x2.toDouble(),
        best.y2.toDouble(),
      );

      final bounds = frameSize ?? Size.zero;
      final scaledRect = bounds.isEmpty
          ? rawRect
          : expandRectWithinBounds(rawRect, bounds, marginFactor: 0.2);
      _smoothBox = _blend(scaledRect, _smoothBox);

      if (now.difference(_lastOcr).inMilliseconds > _intervalOcr) {
        _lastOcr = now;
        final crop = await _crop(bytes, rawRect);
        if (crop != null) ocrPool.push(crop);
      }

      emit(
        state.copyWith(
          isCameraReady: true,
          controller: ev.controller,
          isProcessing: false,
          lastBox: _smoothBox,
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
      imglib.Image image;
      if (Platform.isIOS && img.format.group == ImageFormatGroup.bgra8888) {
        image = _convertBgra(img);
      } else {
        image = _yuvToRgb(img);
      }

      image = _applyOrientation(image);
      return Uint8List.fromList(imglib.encodeJpg(image, quality: 90));
    } catch (e) {
      debugPrint("⚠️ _toRGB error: $e");
      return null;
    }
  }

  imglib.Image _convertBgra(CameraImage img) {
    final plane = img.planes.first;
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final bytesPerPixel = plane.bytesPerPixel ?? 4;
    final width = img.width;
    final height = img.height;

    if (rowStride == width * bytesPerPixel) {
      return imglib.Image.fromBytes(
        width: width,
        height: height,
        bytes: bytes.buffer,
        numChannels: bytesPerPixel,
        order: imglib.ChannelOrder.bgra,
      );
    }

    final buffer = Uint8List(width * height * bytesPerPixel);
    final rowBytes = width * bytesPerPixel;
    for (int y = 0; y < height; y++) {
      final srcOffset = y * rowStride;
      final dstOffset = y * rowBytes;
      final slice = bytes.buffer.asUint8List(srcOffset, rowBytes);
      buffer.setRange(
        dstOffset,
        dstOffset + rowBytes,
        slice,
      );
    }

    return imglib.Image.fromBytes(
      width: width,
      height: height,
      bytes: buffer.buffer,
      numChannels: bytesPerPixel,
      order: imglib.ChannelOrder.bgra,
    );
  }

  imglib.Image _applyOrientation(imglib.Image image) {
    final orientation = _sensorOrientation % 360;
    imglib.Image rotated;
    switch (orientation) {
      case 90:
        rotated = imglib.copyRotate(image, angle: 90);
        break;
      case 180:
        rotated = imglib.copyRotate(image, angle: 180);
        break;
      case 270:
        rotated = imglib.copyRotate(image, angle: 270);
        break;
      default:
        rotated = image;
        break;
    }

    if (_lensDirection == CameraLensDirection.front) {
      rotated = imglib.flipHorizontal(rotated);
    }
    _lastFrameSize = Size(
      rotated.width.toDouble(),
      rotated.height.toDouble(),
    );
    return rotated;
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
    return out;
  }

  Future<Uint8List?> _crop(Uint8List jpeg, Rect rect) async {
    return cropPlateRegionSync(
      jpeg,
      rect,
      marginFactor: 0.25,
      quality: 90,
    );
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
