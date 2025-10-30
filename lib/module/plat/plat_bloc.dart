// ignore_for_file: body_might_complete_normally_catch_error, curly_braces_in_flow_control_structures, depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as imglib;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../service/yolo_service.dart';
import 'plat_event.dart';
import 'plat_state.dart';

class PlateBloc extends Bloc<PlateEvent, PlateState> {
  final YoloService yoloService;

  bool _busy = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);

  Rect? _smoothBox;

  final int intervalMs = 280;

  late final TextRecognizer _ocr = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  PlateBloc({required this.yoloService})
    : super(
        PlateState(
          isCameraReady: false,
          controller: null,
          isProcessing: false,
          lastBox: null,
          lastText: null,
          detectedPlates: [],
          message: null,
        ),
      ) {
    on<StartCamera>(_onStartCamera);
    on<StopCamera>(_onStopCamera);
    on<ProcessCameraImage>(_onProcessCameraImage, transformer: _droppable());
  }

  EventTransformer<T> _droppable<T>() {
    return (events, mapper) => events.asyncExpand((e) => mapper(e));
  }

  Future<void> _onStartCamera(StartCamera ev, Emitter<PlateState> emit) async {
    final controller = CameraController(
      ev.camera,
      ResolutionPreset.low,
      enableAudio: false,
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
    );
    try {
      await controller.initialize();

      await controller.startImageStream((image) {
        if (!_busy) add(ProcessCameraImage(image, controller));
      });

      emit(
        PlateState(
          isCameraReady: true,
          controller: controller,
          isProcessing: false,
          lastBox: null,
          lastText: null,
          detectedPlates: [],
          message: 'Kamera aktif',
        ),
      );
    } catch (e, st) {
      debugPrint("Camera init error: $e\n$st");
      emit(
        PlateState(
          isCameraReady: false,
          controller: null,
          isProcessing: false,
          lastBox: null,
          lastText: null,
          detectedPlates: const [],
          message: 'Gagal init kamera',
        ),
      );
    }
  }

  Future<void> _onStopCamera(StopCamera ev, Emitter<PlateState> emit) async {
    try {
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
        lastText: state.lastText,
        detectedPlates: state.detectedPlates,
        message: 'Kamera berhenti',
      ),
    );
  }

  Future<void> _onProcessCameraImage(
    ProcessCameraImage ev,
    Emitter<PlateState> emit,
  ) async {
    final now = DateTime.now();
    if (now.difference(_lastProcessed).inMilliseconds < intervalMs) return;
    _lastProcessed = now;

    if (_busy) return;
    _busy = true;

    try {
      final jpeg = await compute(_convertImageFast, {
        'image': ev.cameraImage,
        'platformIsIOS': Platform.isIOS,
      });
      if (jpeg == null) {
        _busy = false;
        return;
      }

      final results = await yoloService.detectFromImageBytes(jpeg);
      if (results.isEmpty) {
        _busy = false;
        return;
      }

      results.sort((a, b) => b.score.compareTo(a.score));
      final top = results.first;
      if (top.score < 0.40) {
        _busy = false;
        return;
      }

      final rawBox = Rect.fromLTWH(
        top.x1.toDouble(),
        top.y1.toDouble(),
        (top.x2 - top.x1).toDouble(),
        (top.y2 - top.y1).toDouble(),
      );

      final mappedBox = _translateBox(
        yoloBox: rawBox,
        controller: ev.controller,
        inputSize: yoloService.inputSize,
      );

      _smoothBox = _applySmoothing(mappedBox, _smoothBox);

      emit(
        PlateState(
          isCameraReady: state.isCameraReady,
          controller: state.controller,
          isProcessing: true,
          lastBox: _smoothBox,
          lastText: state.lastText,
          detectedPlates: state.detectedPlates,
          message: 'Plat terdeteksi ${(top.score * 100).toStringAsFixed(1)}%',
        ),
      );

      if (now.difference(_lastOcr).inMilliseconds > 900) {
        _lastOcr = now;

        final text = await _runOcr(jpeg, rawBox, yoloService.inputSize);
        if (text != null && text.isNotEmpty) {
          final updated = List<String>.from(state.detectedPlates);
          if (!updated.contains(text)) updated.add(text);

          emit(
            PlateState(
              isCameraReady: state.isCameraReady,
              controller: state.controller,
              isProcessing: false,
              lastBox: _smoothBox,
              lastText: text,
              detectedPlates: updated,
              message: 'Plat terbaca: $text',
            ),
          );
        } else {
          emit(
            PlateState(
              isCameraReady: state.isCameraReady,
              controller: state.controller,
              isProcessing: false,
              lastBox: _smoothBox,
              lastText: state.lastText,
              detectedPlates: state.detectedPlates,
              message: 'Plat belum terbaca',
            ),
          );
        }
      } else {
        emit(
          PlateState(
            isCameraReady: state.isCameraReady,
            controller: state.controller,
            isProcessing: false,
            lastBox: _smoothBox,
            lastText: state.lastText,
            detectedPlates: state.detectedPlates,
            message: state.message,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('error di process: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  static Future<Uint8List?> _convertImageFast(Map<String, dynamic> args) async {
    try {
      final CameraImage image = args['image'] as CameraImage;
      final bool platformIsIOS = args['platformIsIOS'] as bool;

      if (platformIsIOS && image.format.group == ImageFormatGroup.bgra8888) {
        final plane = image.planes.first;
        final img = imglib.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: plane.bytes.buffer,
          order: imglib.ChannelOrder.bgra,
        );

        final resized = imglib.copyResize(img, width: 960);
        return Uint8List.fromList(imglib.encodeJpg(resized, quality: 70));
      }

      final w = image.width, h = image.height;
      final p0 = image.planes[0];
      final p1 = image.planes[1];
      final p2 = image.planes[2];
      final yRowStride = p0.bytesPerRow;
      final uvRowStride = p1.bytesPerRow;
      final uvPixelStride = p1.bytesPerPixel ?? 1;

      final rgb = imglib.Image(width: w, height: h);
      final yBytes = p0.bytes, uBytes = p1.bytes, vBytes = p2.bytes;

      for (int y = 0; y < h; y++) {
        final pY = y * yRowStride;
        final pUV = (y >> 1) * uvRowStride;
        for (int x = 0; x < w; x++) {
          final uvIndex = pUV + (x >> 1) * uvPixelStride;
          final yp = yBytes[pY + x] & 0xFF;
          final up = uBytes[uvIndex] & 0xFF;
          final vp = vBytes[uvIndex] & 0xFF;

          int r = (yp + 1.402 * (vp - 128)).round();
          int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
          int b = (yp + 1.772 * (up - 128)).round();

          if (r < 0) {
            r = 0;
          } else if (r > 255)
            r = 255;
          if (g < 0) {
            g = 0;
          } else if (g > 255)
            g = 255;
          if (b < 0) {
            b = 0;
          } else if (b > 255)
            b = 255;

          rgb.setPixelRgba(x, y, r, g, b, 255);
        }
      }

      final resized = imglib.copyResize(rgb, width: 960);
      return Uint8List.fromList(imglib.encodeJpg(resized, quality: 70));
    } catch (_) {
      return null;
    }
  }

  Rect _translateBox({
    required Rect yoloBox,
    required CameraController controller,
    required int inputSize,
  }) {
    final preview = controller.value.previewSize!;
    final isPortrait =
        controller.description.sensorOrientation == 90 ||
        controller.description.sensorOrientation == 270;

    final previewW = isPortrait ? preview.height : preview.width;
    final previewH = isPortrait ? preview.width : preview.height;

    final scaleX = previewW / inputSize;
    final scaleY = previewH / inputSize;

    return Rect.fromLTWH(
      yoloBox.left * scaleX,
      yoloBox.top * scaleY,
      yoloBox.width * scaleX,
      yoloBox.height * scaleY,
    );
  }

  Rect _applySmoothing(Rect newBox, Rect? prevBox, {double alpha = 0.30}) {
    if (prevBox == null) return newBox;
    double lerp(double a, double b) => a + (b - a) * alpha;
    return Rect.fromLTWH(
      lerp(prevBox.left, newBox.left),
      lerp(prevBox.top, newBox.top),
      lerp(prevBox.width, newBox.width),
      lerp(prevBox.height, newBox.height),
    );
  }

  Future<String?> _runOcr(Uint8List jpeg, Rect box, int inputSize) async {
    try {
      final img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      final sx = img.width / inputSize;
      final sy = img.height / inputSize;
      final x = (box.left * sx).round().clamp(0, img.width - 1);
      final y = (box.top * sy).round().clamp(0, img.height - 1);
      final w = (box.width * sx).round().clamp(10, img.width - x);
      final h = (box.height * sy).round().clamp(10, img.height - y);

      final pad = (0.08 * w).round();
      final x0 = (x - pad).clamp(0, img.width - 1);
      final y0 = (y - pad).clamp(0, img.height - 1);
      final w0 = (w + pad * 2).clamp(10, img.width - x0);
      final h0 = (h + pad * 2).clamp(10, img.height - y0);

      final cropped = imglib.copyCrop(img, x: x0, y: y0, width: w0, height: h0);

      final pre = imglib.grayscale(cropped);
      final sharp = imglib.adjustColor(pre, contrast: 1.15, brightness: 0.02);

      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final file = File(path);
      await file.writeAsBytes(imglib.encodeJpg(sharp, quality: 95));

      final result = await _ocr.processImage(
        InputImage.fromFilePath(file.path),
      );
      await file.delete().catchError((_) {});

      final lines = <String>[];
      final plate = RegExp(r'^[A-Z]{1,2}\s?\d{1,4}\s?[A-Z]{0,3}$');
      final time = RegExp(r'^\d{2}[:.,]?\d{2}$');

      for (final block in result.blocks) {
        for (final l in block.lines) {
          final t = l.text.trim().toUpperCase().replaceAll('O', '0');
          if (plate.hasMatch(t) || time.hasMatch(t)) lines.add(t);
        }
      }
      return lines.take(2).join('\n');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> close() async {
    try {
      await _ocr.close();
    } catch (_) {}
    await state.controller?.dispose();
    return super.close();
  }
}
