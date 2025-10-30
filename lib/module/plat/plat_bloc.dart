import 'dart:async';
import 'dart:io';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:face_recognition/module/plat/plat_event.dart';
import 'package:face_recognition/module/plat/plat_state.dart';
import 'package:face_recognition/service/yolo_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as imglib;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class PlateBloc extends Bloc<PlateEvent, PlateState> {
  final YoloService yoloService;
  bool _busy = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
  final int intervalMs = 180;
  Rect? _smoothBox;
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
      controller.startImageStream((image) {
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
    if (_busy) return;
    _busy = true;
    _lastProcessed = now;
    try {
      final jpeg = await _convertCameraImageToJpeg(ev.cameraImage);
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
      if (top.score < 0.45) {
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
      if (now.difference(_lastOcr).inMilliseconds > 1000) {
        _lastOcr = now;
        final ocrText = await _runOcrDirect(
          jpeg,
          rawBox,
          yoloService.inputSize,
        );
        if (ocrText != null && ocrText.isNotEmpty) {
          final list = List<String>.from(state.detectedPlates);
          if (!list.contains(ocrText)) list.add(ocrText);
          emit(
            PlateState(
              isCameraReady: state.isCameraReady,
              controller: state.controller,
              isProcessing: false,
              lastBox: _smoothBox,
              lastText: ocrText,
              detectedPlates: list,
              message: 'Plat terbaca:\n$ocrText',
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

  Rect _translateBox({
    required Rect yoloBox,
    required CameraController controller,
    required int inputSize,
  }) {
    final previewSize = controller.value.previewSize!;
    final double scaleX = previewSize.width / inputSize;
    final double scaleY = previewSize.height / inputSize;
    final double left = yoloBox.left * scaleX;
    final double top = yoloBox.top * scaleY;
    final double width = yoloBox.width * scaleX;
    final double height = yoloBox.height * scaleY;
    return Rect.fromLTWH(left, top, width, height);
  }

  Future<String?> _runOcrDirect(Uint8List jpeg, Rect box, int inputSize) async {
    try {
      final img = imglib.decodeImage(jpeg);
      if (img == null) return null;
      final sx = img.width / inputSize;
      final sy = img.height / inputSize;
      final x1 = (box.left * sx).round();
      final y1 = (box.top * sy).round();
      final w = (box.width * sx).round();
      final h = (box.height * sy).round();
      final cropped = imglib.copyCrop(
        img,
        x: x1.clamp(0, img.width - 1),
        y: y1.clamp(0, img.height - 1),
        width: w.clamp(10, img.width - x1),
        height: h.clamp(10, img.height - y1),
      );
      final dir = await getTemporaryDirectory();
      final path = p.join(
        dir.path,
        'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final file = File(path);
      await file.writeAsBytes(imglib.encodeJpg(cropped, quality: 95));
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final result = await recognizer.processImage(
        InputImage.fromFilePath(file.path),
      );
      await recognizer.close();
      await file.delete().catchError((_) {});
      final lines = <String>[];
      final plateRegex = RegExp(r'^[A-Z]{1,2}\s?\d{1,4}\s?[A-Z]{0,3}$');
      final timeRegex = RegExp(r'^\d{2}[:.,]?\d{2}$');
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final text = line.text.trim().toUpperCase();
          if (plateRegex.hasMatch(text) || timeRegex.hasMatch(text)) {
            lines.add(text);
          }
        }
      }
      if (lines.isEmpty) return null;
      return lines.take(2).join('\n');
    } catch (e, st) {
      debugPrint('OCR error: $e\n$st');
      return null;
    }
  }

  Future<Uint8List?> _convertCameraImageToJpeg(CameraImage image) async {
    try {
      if (image.format.group == ImageFormatGroup.bgra8888) {
        final plane = image.planes.first;
        final bgra = plane.bytes;
        final img = imglib.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: bgra.buffer,
          order: imglib.ChannelOrder.bgra,
        );
        return Uint8List.fromList(imglib.encodeJpg(img, quality: 70));
      } else {
        final width = image.width;
        final height = image.height;
        final yPlane = image.planes[0];
        final uPlane = image.planes[1];
        final vPlane = image.planes[2];
        final yRowStride = yPlane.bytesPerRow;
        final uvRowStride = uPlane.bytesPerRow;
        final uvPixelStride = uPlane.bytesPerPixel ?? 1;
        final img = imglib.Image(width: width, height: height);
        for (int y = 0; y < height; y++) {
          for (int x = 0; x < width; x++) {
            final yIndex = y * yRowStride + x;
            final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
            final yp = yPlane.bytes[yIndex];
            final up = uPlane.bytes[uvIndex];
            final vp = vPlane.bytes[uvIndex];
            int r = (yp + 1.370705 * (vp - 128)).clamp(0, 255).toInt();
            int g = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128))
                .clamp(0, 255)
                .toInt();
            int b = (yp + 1.732446 * (up - 128)).clamp(0, 255).toInt();
            img.setPixelRgba(x, y, r, g, b, 255);
          }
        }
        return Uint8List.fromList(imglib.encodeJpg(img, quality: 70));
      }
    } catch (e) {
      debugPrint('convert error: $e');
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
  final scoreThreshold = args['scoreThreshold'] as double;
  final options = InterpreterOptions();
  if (Platform.isAndroid) {
    options.useNnApiForAndroid = true;
  } else if (Platform.isIOS) {
    options.addDelegate(XNNPackDelegate());
  }
  final interpreter = Interpreter.fromBuffer(modelBytes, options: options);

  final img = imglib.decodeImage(jpeg);
  if (img == null) return [];
  final resized = imglib.copyResize(img, width: inputSize, height: inputSize);
  final input = List<double>.filled(inputSize * inputSize * 3, 0.0);
  int index = 0;
  for (int y = 0; y < inputSize; y++) {
    for (int x = 0; x < inputSize; x++) {
      final pixel = resized.getPixel(x, y);
      input[index++] = pixel.r / 255.0;
      input[index++] = pixel.g / 255.0;
      input[index++] = pixel.b / 255.0;
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
  final results = <YoloResult>[];
  for (int i = 0; i < 8400; i++) {
    final score = confs[i];
    if (score < scoreThreshold) continue;
    final x = xs[i];
    final y = ys[i];
    final w = ws[i];
    final h = hs[i];
    final x1 = ((x - w / 2) * inputSize).clamp(0, inputSize - 1).round();
    final y1 = ((y - h / 2) * inputSize).clamp(0, inputSize - 1).round();
    final x2 = ((x + w / 2) * inputSize).clamp(0, inputSize - 1).round();
    final y2 = ((y + h / 2) * inputSize).clamp(0, inputSize - 1).round();
    results.add(
      YoloResult(x1: x1, y1: y1, x2: x2, y2: y2, score: score, label: 'plate'),
    );
  }
  return results;
}
