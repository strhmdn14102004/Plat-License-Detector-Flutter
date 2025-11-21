// ignore_for_file: unused_field, body_might_complete_normally_catch_error

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as imglib;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class OcrIsolatePool {
  final _queue = StreamController<Uint8List>();
  bool _running = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);

  final _onResult = StreamController<String>.broadcast();
  Stream<String> get results => _onResult.stream;

  // ---------------------------------------------------------------------------
  // START QUEUE
  // ---------------------------------------------------------------------------
  void start() {
    if (_running) return;
    _running = true;

    _queue.stream.asyncMap(_process).listen((text) {
      if (text != null && text.isNotEmpty) {
        _onResult.add(text);
      }
    });
  }

  void push(Uint8List jpeg) => _queue.add(jpeg);

  // ---------------------------------------------------------------------------
  // MAP HURUF → ANGKA DI BAGIAN TENGAH (KHUSUS DIGIT)
  // ---------------------------------------------------------------------------
  String fixMiddleDigits(String mid) {
    return mid
        .replaceAll('A', '4')
        .replaceAll('Z', '2')
        .replaceAll('S', '5')
        .replaceAll('B', '8')
        .replaceAll('O', '0')
        .replaceAll('I', '1')
        .replaceAll('T', '7');
  }

  // Sharpen kernel (3x3)
  final List<num> sharpenKernel = const [0, -1, 0, -1, 5, -1, 0, -1, 0];

  // ---------------------------------------------------------------------------
  // CORE OCR PIPELINE
  // ---------------------------------------------------------------------------
  Future<String?> _process(Uint8List jpeg) async {
    try {
      final now = DateTime.now();
      _lastProcessed = now;

      // Decode image
      var img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      // -----------------------------------------------------------------------
      // DETEKSI KIRA-KIRA PLAT GELAP / TERANG
      // -----------------------------------------------------------------------
      final thumb = imglib.copyResize(img, width: 40);
      final grayBytes = thumb.getBytes().map((b) => b & 0xFF).toList();
      final meanGray = grayBytes.isEmpty
          ? 128.0
          : grayBytes.reduce((a, b) => a + b) / grayBytes.length;

      final bool isBlackPlate = meanGray < 90;

      // -----------------------------------------------------------------------
      // PRE-PROCESSING SESUAI PLAT
      // -----------------------------------------------------------------------
      if (isBlackPlate) {
        // Plat hitam (tulisan putih)
        img = imglib.adjustColor(img, brightness: 0.45, contrast: 1.75);
        img = imglib.convolution(img, filter: sharpenKernel, div: 1, offset: 0);
      } else {
        // Plat terang (putih / kuning)
        img = imglib.adjustColor(img, brightness: 0.12, contrast: 1.35);
        img = imglib.convolution(img, filter: sharpenKernel, div: 1, offset: 0);
        // Sedikit blur buat ilangin noise tipis
        img = imglib.gaussianBlur(img, radius: 1);
      }

      // Simpan ke file sementara untuk MLKit
      final tmp = await getTemporaryDirectory();
      final file = File(
        p.join(tmp.path, 'ocr_${now.millisecondsSinceEpoch}.jpg'),
      )..writeAsBytesSync(imglib.encodeJpg(img, quality: 95));

      // -----------------------------------------------------------------------
      // GOOGLE ML KIT TEXT RECOGNITION
      // -----------------------------------------------------------------------
      final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final input = InputImage.fromFile(file);
      final result = await recognizer.processImage(input);
      await recognizer.close();
      await file.delete().catchError((_) {});

      final lines = <String>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final txt = line.text.trim().toUpperCase();
          if (txt.isNotEmpty) lines.add(txt);
        }
      }

      if (lines.isEmpty) return '';

      // Urutkan yang paling banyak digit dulu (biasanya bagian nomor plat)
      lines.sort((a, b) {
        final da = RegExp(r'\d').allMatches(a).length;
        final db = RegExp(r'\d').allMatches(b).length;
        return db.compareTo(da);
      });

      // -----------------------------------------------------------------------
      // NORMALIZER PLAT INDONESIA
      // - prefix : 1–3 huruf
      // - mid    : 1–5 digit
      // - suffix : 0–4 huruf
      // -----------------------------------------------------------------------
      String normalize(String raw) {
        var t = raw
            .replaceAll(RegExp(r'[^A-Z0-9]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();

        final parts = t.split(' ').where((e) => e.isNotEmpty).toList();
        if (parts.length < 2) return t;

        // ---------------- PREFIX (HURUF SAJA) ----------------
        String prefix = parts[0];
        prefix = prefix
            .replaceAll('0', 'O')
            .replaceAll('1', 'I')
            .replaceAll('2', 'Z')
            .replaceAll('4', 'A')
            .replaceAll('5', 'S')
            .replaceAll('6', 'G')
            .replaceAll('8', 'B');

        // Harus 1-3 huruf
        if (!RegExp(r'^[A-Z]{1,3}$').hasMatch(prefix)) {
          return t;
        }

        // ---------------- MIDDLE (ANGKA SAJA) ----------------
        String mid = parts[1];
        mid = fixMiddleDigits(mid);
        mid = mid.replaceAll(RegExp(r'[A-Z]'), '');

        if (!RegExp(r'^\d{1,5}$').hasMatch(mid)) {
          return t;
        }

        // ---------------- SUFFIX (HURUF SAJA, OPSIONAL) ------
        String suffix = '';
        if (parts.length > 2) {
          // Gabungkan semua token setelah angka jadi satu suffix
          suffix = parts.sublist(2).join('');
          suffix = suffix
              .replaceAll('0', 'O')
              .replaceAll('1', 'I')
              .replaceAll('2', 'Z')
              .replaceAll('5', 'S')
              .replaceAll('6', 'G')
              .replaceAll('8', 'B')
              .replaceAll(RegExp(r'[^A-Z]'), '');
        }

        if (suffix.isNotEmpty && !RegExp(r'^[A-Z]{1,4}$').hasMatch(suffix)) {
          // Kalau suffix kacau (ada digit nyelip, dsb) → buang suffix
          return '$prefix $mid'.trim();
        }

        return '$prefix $mid $suffix'.trim();
      }

      // -----------------------------------------------------------------------
      // DAFTAR PREFIX SAH PLAT INDONESIA
      // -----------------------------------------------------------------------
      const validPrefix = [
        'BL',
        'BB',
        'BK',
        'BA',
        'BM',
        'BH',
        'BD',
        'BP',
        'BG',
        'BN',
        'BE',
        'A',
        'B',
        'D',
        'E',
        'F',
        'T',
        'Z',
        'G',
        'H',
        'K',
        'R',
        'AA',
        'AD',
        'AB',
        'L',
        'M',
        'N',
        'P',
        'S',
        'W',
        'AE',
        'AG',
        'DK',
        'DR',
        'EA',
        'DH',
        'EB',
        'ED',
        'KB',
        'DA',
        'KH',
        'KT',
        'KU',
        'DB',
        'DL',
        'DM',
        'DN',
        'DT',
        'DD',
        'DC',
        'DE',
        'DG',
        'PA',
        'PB',
        'RI',
        'CC',
        'CD',
      ];

      // Coba tiap line yang sudah diurutkan (digit terbanyak dulu)
      for (final raw in lines) {
        final txt = normalize(raw);
        final parts = txt.split(' ').where((e) => e.isNotEmpty).toList();
        if (parts.isEmpty) continue;

        final prefix = parts.first;
        if (!validPrefix.contains(prefix)) continue;

        // Valid & sudah normal → kirim
        debugPrint('🔍 OCR extracted = $txt');
        return txt;
      }

      // Tidak ada yang valid, tapi kita tetap bisa balikin kandidat terbaik mentah
      return '';
    } catch (e, st) {
      debugPrint('❌ OCR ERROR: $e\n$st');
      return null;
    }
  }

  void dispose() {
    _queue.close();
    _onResult.close();
  }
}
