// ignore_for_file: depend_on_referenced_packages, invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
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
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  Rect? _smoothBox;

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
        ),
      ) {
    on<StartCamera>(_onStartCamera);
    on<StopCamera>(_onStopCamera);
    on<ProcessCameraImage>(_onProcessCameraImage);

    ocrPool.results.listen((text) {
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
          message: 'Plat terbaca:\n$text',
        ),
      );
    });
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
      ocrPool.start();
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
    } catch (e) {
      debugPrint("Camera init error: $e");
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
    if (!state.isCameraReady || _busy) return;
    if (now.difference(_lastProcessed).inMilliseconds < 150) return;

    _busy = true;
    _lastProcessed = now;
    try {
      final jpeg = await _convertCameraImageToJpeg(ev.cameraImage);
      if (jpeg == null) {
        _busy = false;
        return;
      }

      final results = await yoloPool.detect(jpeg);
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
          message: 'Plat ${(top.score * 100).toStringAsFixed(1)}%',
        ),
      );

      ocrPool.push(jpeg);
    } catch (e) {
      debugPrint("Error process: $e");
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

  Future<Uint8List?> _convertCameraImageToJpeg(CameraImage image) async {
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

  @override
  Future<void> close() async {
    await state.controller?.dispose();
    yoloPool.dispose();
    ocrPool.dispose();
    return super.close();
  }
}
