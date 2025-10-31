// ignore_for_file: depend_on_referenced_packages, body_might_complete_normally_catch_error
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

class PlateBloc extends Bloc<PlateEvent, PlateState> {
  final YoloService yoloService;

  bool _busy = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastOcr = DateTime.fromMillisecondsSinceEpoch(0);
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
      imageFormatGroup: Platform.isIOS
          ? ImageFormatGroup.bgra8888
          : ImageFormatGroup.yuv420,
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
    if (!state.isCameraReady || ev.controller.value.isTakingPicture) return;
    if (now.difference(_lastProcessed).inMilliseconds < 180) return;
    if (_busy) return;

    _busy = true;
    _lastProcessed = now;

    try {
      final jpeg = await _convertCameraImageToJpeg(ev.cameraImage);
      if (jpeg == null) {
        _busy = false;
        return;
      }

      // Jalankan YOLO di isolate (GPU aktif di iOS)
      final results = await yoloService.detectFromImageBytes(jpeg);
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
          message: 'Plat ${(top.score * 100).toStringAsFixed(1)}%',
        ),
      );

      if (now.difference(_lastOcr).inMilliseconds >=
          (Platform.isIOS ? 700 : 1600)) {
        _lastOcr = now;
        Future.microtask(() async {
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
        });
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
    final isIOS = Platform.isIOS;
    final double scaleX = previewSize.width / inputSize;
    final double scaleY = previewSize.height / inputSize;

    double left = yoloBox.left * scaleX;
    double top = yoloBox.top * scaleY;
    double width = yoloBox.width * scaleX;
    double height = yoloBox.height * scaleY;

    if (isIOS) {
      final rotatedLeft = previewSize.width - (top + height);
      final rotatedTop = left;
      final rotatedW = height;
      final rotatedH = width;
      return Rect.fromLTWH(rotatedLeft, rotatedTop, rotatedW, rotatedH);
    }
    return Rect.fromLTWH(left, top, width, height);
  }

  Future<String?> _runOcrDirect(Uint8List jpeg, Rect box, int inputSize) async {
    try {
      var img = imglib.decodeImage(jpeg);
      if (img == null) return null;
      if (Platform.isIOS && img.height > img.width) {
        img = imglib.copyRotate(img, angle: 90);
      }

      final sx = img.width / inputSize;
      final sy = img.height / inputSize;
      int x1 = (box.left * sx).round();
      int y1 = (box.top * sy).round();
      int w = (box.width * sx).round();
      int h = (box.height * sy).round();

      final cropped = imglib.copyCrop(img, x: x1, y: y1, width: w, height: h);
      final tmp = await getTemporaryDirectory();
      final file = File(
        p.join(tmp.path, 'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg'),
      )..writeAsBytesSync(imglib.encodeJpg(cropped, quality: 90), flush: true);
      await Future.delayed(const Duration(milliseconds: 40));

      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final input = InputImage.fromFile(file);
      final result = await recognizer.processImage(input);
      await recognizer.close();
      await file.delete().catchError((_) {});

      final buffer = <String>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final txt = line.text.trim().toUpperCase();
          if (txt.isNotEmpty) buffer.add(txt);
        }
      }
      return buffer.isEmpty ? null : buffer.take(2).join('\n');
    } catch (e, st) {
      debugPrint('OCR error: $e\n$st');
      return null;
    }
  }

  Future<Uint8List?> _convertCameraImageToJpeg(CameraImage image) async {
    try {
      if (image.format.group == ImageFormatGroup.bgra8888) {
        final plane = image.planes.first;
        final img = imglib.Image.fromBytes(
          width: image.width,
          height: image.height,
          bytes: plane.bytes.buffer,
          order: imglib.ChannelOrder.bgra,
        );
        return Uint8List.fromList(imglib.encodeJpg(img, quality: 60));
      } else {
        return null;
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
