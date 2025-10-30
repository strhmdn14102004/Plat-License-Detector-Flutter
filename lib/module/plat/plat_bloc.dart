// ignore_for_file: body_might_complete_normally_catch_error, depend_on_referenced_packages

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
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../service/yolo_service.dart';
import 'plat_event.dart';
import 'plat_state.dart';

class PlateBloc extends Bloc<PlateEvent, PlateState> {
  final YoloService yoloService;

  bool _busy = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
  Rect? _smoothBox;

  final int intervalMs = 130;

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
    on<ProcessCameraImage>(_onProcessCameraImage);
  }

  Future<void> _onStartCamera(StartCamera ev, Emitter<PlateState> emit) async {
    final controller = CameraController(
      ev.camera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
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
    _busy = true;

    try {
      final jpeg = await compute(_convertToJpegIsolate, ev.cameraImage);
      if (jpeg == null) {
        _busy = false;
        return;
      }

      final results = await compute(_detectInIsolate, {
        'jpeg': jpeg,
        'modelBytes': yoloService.modelBytes,
        'inputSize': yoloService.inputSize,
        'scoreThreshold': yoloService.scoreThreshold,
      });

      if (results.isEmpty) {
        _busy = false;
        return;
      }

      results.sort((a, b) => b.score.compareTo(a.score));
      final top = results.first;
      if (top.score < 0.4) {
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
        }
      }
    } catch (e, st) {
      debugPrint('error di process: $e\n$st');
    } finally {
      _busy = false;
    }
  }

  static Future<Uint8List?> _convertToJpegIsolate(CameraImage image) async {
    try {
      final width = image.width;
      final height = image.height;
      final y = image.planes[0];
      final u = image.planes[1];
      final v = image.planes[2];

      final yRowStride = y.bytesPerRow;
      final uvRowStride = u.bytesPerRow;
      final uvPixelStride = u.bytesPerPixel ?? 1;

      final img = imglib.Image(width: width, height: height);
      for (int y0 = 0; y0 < height; y0++) {
        for (int x = 0; x < width; x++) {
          final yIndex = y0 * yRowStride + x;
          final uvIndex = (y0 ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
          final yp = y.bytes[yIndex];
          final up = u.bytes[uvIndex];
          final vp = v.bytes[uvIndex];
          int r = (yp + 1.370705 * (vp - 128)).clamp(0, 255).toInt();
          int g = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128))
              .clamp(0, 255)
              .toInt();
          int b = (yp + 1.732446 * (up - 128)).clamp(0, 255).toInt();
          img.setPixelRgba(x, y0, r, g, b, 255);
        }
      }
      return Uint8List.fromList(imglib.encodeJpg(img, quality: 70));
    } catch (e) {
      debugPrint('convert isolate error: $e');
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

  Rect _applySmoothing(Rect newBox, Rect? prevBox, {double alpha = 0.3}) {
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

      final cropped = imglib.copyCrop(img, x: x, y: y, width: w, height: h);
      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final file = File(path);
      await file.writeAsBytes(imglib.encodeJpg(cropped, quality: 95));

      final rec = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await rec.processImage(InputImage.fromFilePath(file.path));
      await rec.close();
      await file.delete().catchError((_) {});

      final lines = <String>[];
      final plate = RegExp(r'^[A-Z]{1,2}\s?\d{1,4}\s?[A-Z]{0,3}$');
      final time = RegExp(r'^\d{2}[:.,]?\d{2}$');

      for (final block in result.blocks) {
        for (final l in block.lines) {
          final t = l.text.trim().toUpperCase();
          if (plate.hasMatch(t) || time.hasMatch(t)) lines.add(t);
        }
      }
      return lines.take(2).join('\n');
    } catch (e, st) {
      debugPrint('OCR error: $e\n$st');
      return null;
    }
  }

  @override
  Future<void> close() async {
    await state.controller?.dispose();
    return super.close();
  }
}

Future<List<YoloResult>> _detectInIsolate(Map<String, dynamic> args) async {
  final jpeg = args['jpeg'] as Uint8List;
  final modelBytes = args['modelBytes'] as Uint8List;
  final inputSize = args['inputSize'] as int;
  final threshold = args['scoreThreshold'] as double;

  final interpreter = Interpreter.fromBuffer(
    modelBytes,
    options: InterpreterOptions()..useNnApiForAndroid = true,
  );
  final img = imglib.decodeImage(jpeg);
  if (img == null) return [];

  final resized = imglib.copyResize(img, width: inputSize, height: inputSize);
  final input = List<double>.filled(inputSize * inputSize * 3, 0.0);
  int i = 0;
  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final p = resized.getPixel(x, y);
      input[i++] = p.r / 255.0;
      input[i++] = p.g / 255.0;
      input[i++] = p.b / 255.0;
    }
  }

  final output = List.generate(
    1,
    (_) => List.generate(5, (_) => List<double>.filled(8400, 0.0)),
  );
  interpreter.run(input.reshape([1, inputSize, inputSize, 3]), output);
  interpreter.close();

  final xs = output[0][0];
  final ys = output[0][1];
  final ws = output[0][2];
  final hs = output[0][3];
  final confs = output[0][4];

  final res = <YoloResult>[];
  for (int j = 0; j < 8400; j++) {
    final s = confs[j];
    if (s < threshold) continue;
    final x = xs[j], y = ys[j], w = ws[j], h = hs[j];
    final x1 = ((x - w / 2) * inputSize).clamp(0, inputSize - 1).round();
    final y1 = ((y - h / 2) * inputSize).clamp(0, inputSize - 1).round();
    final x2 = ((x + w / 2) * inputSize).clamp(0, inputSize - 1).round();
    final y2 = ((y + h / 2) * inputSize).clamp(0, inputSize - 1).round();
    res.add(
      YoloResult(x1: x1, y1: y1, x2: x2, y2: y2, score: s, label: 'plate'),
    );
  }
  return res;
}
