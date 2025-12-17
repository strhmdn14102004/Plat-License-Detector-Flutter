import 'dart:io';

import 'package:anpr/model/plate_result.dart';
import 'package:anpr/module/ANPR/anpr_event.dart';
import 'package:anpr/module/ANPR/anpr_state.dart';
import 'package:anpr/services/yolo.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class AnprBloc extends Bloc<AnprEvent, AnprState> {
  final ImagePicker _picker = ImagePicker();
  final TextRecognizer _textRecognizer = TextRecognizer();

  late final YoloIsolatePool _yolo;
  late final Uint8List _yoloModel;

  AnprBloc() : super(AnprInitial()) {
    on<PickImageEvent>(_onPickImage);
    on<ProcessImageEvent>(_onProcessImage);
    on<SubmitManualCropEvent>(_onManualCropSubmit);
    on<ResetEvent>(_onReset);

    _initYolo();
  }

  Future<void> _initYolo() async {
    _yoloModel = await rootBundle
        .load('assets/models/license_plate_detector_float16.tflite')
        .then((b) => b.buffer.asUint8List());

    _yolo = YoloIsolatePool(numWorkers: 2);
    await _yolo.init(_yoloModel, 640, 0.4);
  }

  Future<void> _onPickImage(
    PickImageEvent event,
    Emitter<AnprState> emit,
  ) async {
    emit(AnprLoading());

    final XFile? image = await _picker.pickImage(
      source: event.source,
      imageQuality: 100,
    );

    if (image == null) {
      emit(AnprError('Tidak ada gambar dipilih'));
      return;
    }

    add(ProcessImageEvent(image.path));
  }

  Future<void> _onProcessImage(
    ProcessImageEvent event,
    Emitter<AnprState> emit,
  ) async {
    emit(AnprLoading());

    final bytes = await File(event.imagePath).readAsBytes();
    final detections = await _yolo.detect(bytes);

    if (detections.isEmpty) {
      emit(
        AnprManualCrop(imagePath: event.imagePath, initialQuad: _defaultQuad()),
      );
      return;
    }

    detections.sort((a, b) => b.score.compareTo(a.score));
    final box = detections.first;

    final cropPath = await _cropByBox(event.imagePath, box);
    if (cropPath == null) {
      emit(
        AnprManualCrop(imagePath: event.imagePath, initialQuad: _defaultQuad()),
      );
      return;
    }

    await _runOcr(cropPath, event.imagePath, emit);
  }

  Future<String?> _cropByBox(String imagePath, dynamic box) async {
    final bytes = await File(imagePath).readAsBytes();
    final raw = img.decodeImage(bytes);
    if (raw == null) return null;

    final image = img.bakeOrientation(raw);

    final int x = box.x1.clamp(0, image.width);
    final int y = box.y1.clamp(0, image.height);
    final int w = (box.x2 - box.x1).clamp(1, image.width - x);
    final int h = (box.y2 - box.y1).clamp(1, image.height - y);

    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);

    final out = imagePath.replaceFirst('.jpg', '_auto.jpg');
    await File(out).writeAsBytes(img.encodeJpg(cropped, quality: 100));
    return out;
  }

  Future<void> _onManualCropSubmit(
    SubmitManualCropEvent event,
    Emitter<AnprState> emit,
  ) async {
    emit(AnprLoading());

    final croppedPath = await _cropByQuad(event.imagePath, event.quad);
    if (croppedPath == null) {
      emit(AnprError('Gagal crop manual'));
      return;
    }

    await _runOcr(croppedPath, event.imagePath, emit);
  }

  Future<void> _runOcr(
    String croppedPath,
    String originalPath,
    Emitter<AnprState> emit,
  ) async {
    try {
      final inputImage = InputImage.fromFilePath(croppedPath);
      final text = await _textRecognizer.processImage(inputImage);

      if (kDebugMode) {
        print('📝 OCR Full Text: ${text.text}');
      }
      if (kDebugMode) {
        print('📝 OCR Blocks: ${text.blocks.length}');
      }

      if (text.text.isEmpty) {
        emit(AnprError('Tidak ada teks terdeteksi. Coba crop lebih presisi.'));
        return;
      }

      final plate = _extractPlate(text.text);
      if (plate == null) {
        emit(
          AnprError(
            'Plat tidak terbaca.\n'
            'Text terdeteksi: ${text.text.replaceAll('\n', ' ')}\n'
            'Coba crop ulang dengan lebih presisi.',
          ),
        );
        return;
      }

      emit(
        AnprSuccess(
          PlateResult(
            plateNumber: plate,
            fullText: text.text,
            timestamp: DateTime.now(),
            imagePath: originalPath,
            croppedImagePath: croppedPath,
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ OCR Error: $e');
      }
      emit(AnprError('Error OCR: $e'));
    }
  }

  Future<String?> _cropByQuad(String path, List<Offset> quad) async {
    final bytes = await File(path).readAsBytes();
    final raw = img.decodeImage(bytes);
    if (raw == null) return null;

    final image = img.bakeOrientation(raw);

    final minX = quad.map((e) => e.dx).reduce((a, b) => a < b ? a : b);
    final minY = quad.map((e) => e.dy).reduce((a, b) => a < b ? a : b);
    final maxX = quad.map((e) => e.dx).reduce((a, b) => a > b ? a : b);
    final maxY = quad.map((e) => e.dy).reduce((a, b) => a > b ? a : b);

    final x = (minX * image.width).round().clamp(0, image.width - 1);
    final y = (minY * image.height).round().clamp(0, image.height - 1);
    final w = ((maxX - minX) * image.width).round();
    final h = ((maxY - minY) * image.height).round();

    final cropW = w.clamp(20, image.width - x);
    final cropH = h.clamp(20, image.height - y);

    if (cropW < 20 || cropH < 20) {
      return null;
    }

    var crop = img.copyCrop(image, x: x, y: y, width: cropW, height: cropH);

    if (cropW < 200 || cropH < 100) {
      final scale = cropW < cropH ? 200 / cropW : 100 / cropH;
      final newW = (cropW * scale).round();
      final newH = (cropH * scale).round();
      crop = img.copyResize(crop, width: newW, height: newH);
    }

    crop = img.adjustColor(crop, contrast: 1.2, brightness: 1.05);

    final out = path.replaceFirst('.jpg', '_manual.jpg');
    await File(out).writeAsBytes(img.encodeJpg(crop, quality: 100));
    return out;
  }

  List<Offset> _defaultQuad() => const [
    Offset(0.2, 0.4),
    Offset(0.8, 0.4),
    Offset(0.8, 0.6),
    Offset(0.2, 0.6),
  ];

  String? _extractPlate(String text) {
    final normalized = text
        .toUpperCase()
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (kDebugMode) {
      print('🔍 Normalized OCR: $normalized');
    }

    final riPattern = RegExp(r'\bRI\s*\d{1,2}\b');
    final riMatch = riPattern.firstMatch(normalized);
    if (riMatch != null) {
      final plate = riMatch.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
      if (kDebugMode) {
        print('🇮🇩 RI Plate detected: $plate');
      }
      return plate;
    }

    final generalPatterns = [
      RegExp(r'\b[A-Z]{1,2}\s*\d{1,4}\s*[A-Z]{1,3}\b'),
      RegExp(r'\b[A-Z]{1,2}\s*\d{1,4}\b'),
    ];

    for (final pattern in generalPatterns) {
      final match = pattern.firstMatch(normalized);
      if (match != null) {
        final plate = match.group(0)!.replaceAll(RegExp(r'\s+'), ' ');
        if (kDebugMode) {
          print('✅ Plate detected: $plate');
        }
        return plate;
      }
    }

    if (kDebugMode) {
      print('❌ No plate matched');
    }
    return null;
  }

  void _onReset(ResetEvent e, Emitter<AnprState> emit) {
    emit(AnprInitial());
  }

  @override
  Future<void> close() {
    _textRecognizer.close();
    _yolo.dispose();
    return super.close();
  }
}
