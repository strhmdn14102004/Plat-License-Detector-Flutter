// ignore_for_file: always_specify_types

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

  /// ===============================
  /// 🇮🇩 PREFIX PLAT RESMI INDONESIA
  /// ===============================
  static const Set<String> validPlatePrefixes = {
    // 1 huruf
    'A',
    'B',
    'D',
    'E',
    'F',
    'G',
    'H',
    'K',
    'L',
    'M',
    'N',
    'P',
    'R',
    'S',
    'T',
    'W',
    'Z',

    // 2 huruf
    'AA', 'AB', 'AD', 'AE', 'AG',
    'BA', 'BB', 'BD', 'BE', 'BG', 'BH', 'BK', 'BL', 'BM', 'BN', 'BP',
    'DA',
    'DB',
    'DC',
    'DD',
    'DE',
    'DG',
    'DH',
    'DK',
    'DL',
    'DM',
    'DN',
    'DP',
    'DR',
    'DT',
    'DW',
    'EA', 'EB', 'ED',
    'KB', 'KH', 'KT', 'KU',
    'PA', 'PB',
  };

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

  // =============================================================
  // 📸 PICK IMAGE
  // =============================================================
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

  // =============================================================
  // 🧠 YOLO DETECTION
  // =============================================================
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
    final YoloResult box = detections.first;

    final cropPath = await _cropByBox(event.imagePath, box);
    if (cropPath == null) {
      emit(
        AnprManualCrop(imagePath: event.imagePath, initialQuad: _defaultQuad()),
      );
      return;
    }

    await _runOcr(cropPath, event.imagePath, emit);
  }

  // =============================================================
  // ✂️ AUTO CROP
  // =============================================================
  Future<String?> _cropByBox(String imagePath, YoloResult box) async {
    final bytes = await File(imagePath).readAsBytes();
    final raw = img.decodeImage(bytes);
    if (raw == null) return null;

    final image = img.bakeOrientation(raw);

    final int x = box.x1.clamp(0, image.width);
    final int y = box.y1.clamp(0, image.height);
    final int w = (box.x2 - box.x1).clamp(1, image.width - x);
    final int h = (box.y2 - box.y1).clamp(1, image.height - y);

    final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);

    final out = _appendSuffix(imagePath, '_auto');
    await File(out).writeAsBytes(img.encodeJpg(cropped, quality: 100));
    return out;
  }

  // =============================================================
  // ✂️ MANUAL CROP SUBMIT
  // =============================================================
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

  // =============================================================
  // 🔍 OCR
  // =============================================================
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

      // OCR KOSONG → MANUAL CROP
      if (text.text.trim().isEmpty) {
        emit(
          AnprManualCrop(imagePath: originalPath, initialQuad: _defaultQuad()),
        );
        return;
      }

      final plate = _extractPlate(text.text);

      // TIDAK VALID → MANUAL CROP
      if (plate == null) {
        emit(
          AnprManualCrop(imagePath: originalPath, initialQuad: _defaultQuad()),
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
      emit(
        AnprManualCrop(imagePath: originalPath, initialQuad: _defaultQuad()),
      );
    }
  }

  // =============================================================
  // ✂️ MANUAL CROP ENGINE
  // =============================================================
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

    final out = _appendSuffix(path, '_manual');
    await File(out).writeAsBytes(img.encodeJpg(crop, quality: 100));
    return out;
  }

  // =============================================================
  // 🇮🇩 PLATE VALIDATOR (PERPOL 7/2021)
  // =============================================================
  String? _extractPlate(String text) {
    // 1. CLEANING / NORMALISASI
    // Hapus simbol aneh, sisakan Huruf, Angka, dan Spasi
    final normalized = text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), ' ') // Ubah simbol jadi spasi
        .replaceAll(RegExp(r'\s+'), ' ') // Satukan spasi berlebih
        .trim();

    if (kDebugMode) {
      print('🔍 Normalized OCR: $normalized');
    }

    // 2. REGEX DEFINITIONS

    // A. PLAT KHUSUS (RI / CD / CC)
    // Format: Kode (RI/CD/CC) + Spasi + Angka (1-9999, TIDAK BOLEH 0 DI DEPAN)
    // Contoh: RI 1, CD 12, RI 42
    final specialPattern = RegExp(r'\b(RI|CD|CC)\s+([1-9][0-9]{0,3})\b');

    // B. PLAT UMUM (SIPIL/DINAS)
    // Format: Kode Wilayah + Spasi + Angka + (Opsional) Huruf Belakang
    // Penjelasan Regex Angka [1-9][0-9]{0,3}:
    // - [1-9]      : Digit pertama WAJIB 1-9 (Mencegah "0124")
    // - [0-9]{0,3} : Diikuti 0 sampai 3 digit angka apa saja (0-9)
    // Contoh Valid: F 1, B 1234 KCA
    // Contoh Invalid: F 01, B 0123 ABC
    final standardPattern = RegExp(
      r'\b([A-Z]{1,2})\s+([1-9][0-9]{0,3})(?:\s+([A-Z]{1,3}))?\b',
    );

    // 3. EKSEKUSI PENCOCOKAN

    // Cek Prioritas 1: Plat Khusus (RI/CD)
    final specialMatch = specialPattern.firstMatch(normalized);
    if (specialMatch != null) {
      // Group 0 mengambil full string yang cocok (misal: "RI 1")
      final result = specialMatch.group(0);
      if (kDebugMode) print('✅ Special plate found: $result');
      return result;
    }

    // Cek Prioritas 2: Plat Umum (Standard)
    // Kita loop semua kemungkinan match untuk memverifikasi Kode Wilayah
    for (final match in standardPattern.allMatches(normalized)) {
      final prefix = match.group(1)!; // Kode Wilayah (F, B, DK)
      final number = match.group(2)!; // Nomor (Pasti tidak diawali 0)
      final suffix = match.group(
        3,
      ); // Huruf Belakang (Bisa null untuk Plat Dinas F 1)

      // Validasi Prefix harus ada di daftar Samsat (validPlatePrefixes)
      // Pastikan set 'validPlatePrefixes' Anda sudah lengkap di bagian atas Class
      if (!validPlatePrefixes.contains(prefix)) {
        if (kDebugMode) {
          print('❌ Invalid prefix found: $prefix in ${match.group(0)}');
        }
        continue;
      }

      // Gabungkan hasil yang bersih
      // join(' ') akan otomatis memberi spasi antar elemen
      final plate = [prefix, number, if (suffix != null) suffix].join(' ');

      if (kDebugMode) {
        print('✅ Valid standard plate: $plate');
      }

      return plate;
    }

    if (kDebugMode) {
      print('❌ No valid Indonesian plate found');
    }
    return null;
  }

  List<Offset> _defaultQuad() => const [
    Offset(0.2, 0.4),
    Offset(0.8, 0.4),
    Offset(0.8, 0.6),
    Offset(0.2, 0.6),
  ];

  String _appendSuffix(String path, String suffix) {
    final ext = path.split('.').last;
    return path.replaceFirst('.$ext', '$suffix.$ext');
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
