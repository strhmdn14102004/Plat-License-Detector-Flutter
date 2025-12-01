// ignore_for_file: body_might_complete_normally_catch_error

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

  void start() {
    if (_running) return;
    _running = true;
    _queue.stream.asyncMap(_process).listen((text) {
      if (text != null && text.isNotEmpty) _onResult.add(text);
    });
  }

  void push(Uint8List jpeg) => _queue.add(jpeg);

  imglib.Image preprocessPlate(imglib.Image src) {
    final w = src.width;
    final h = src.height;

    final gray = imglib.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = src.getPixel(x, y);
        final lum = ((0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(
          0,
          255,
        )).toInt();
        gray.setPixelRgba(x, y, lum, lum, lum, 255);
      }
    }

    final highContrast = imglib.adjustColor(
      gray,
      contrast: 1.25,
      brightness: 0.02,
    );

    final sharpen = imglib.convolution(
      highContrast,
      filter: const [0, -1, 0, -1, 5, -1, 0, -1, 0],
      div: 1,
    );

    final bw = imglib.Image(width: w, height: h);

    int sampleCount = 0;
    int sumLum = 0;

    for (int y = 0; y < h; y += 10) {
      for (int x = 0; x < w; x += 10) {
        final p = sharpen.getPixel(x, y);
        final lum = (p.r).toInt();
        sumLum += lum;
        sampleCount++;
      }
    }

    if (sampleCount == 0) return sharpen;

    double avgLum = sumLum / sampleCount;
    avgLum = avgLum.clamp(60.0, 160.0).toDouble();

    final threshold = (avgLum * 0.85).toInt();

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = sharpen.getPixel(x, y);
        final lum = (p.r).toInt();
        if (lum > threshold) {
          bw.setPixelRgba(x, y, 255, 255, 255, 255);
        } else {
          bw.setPixelRgba(x, y, 0, 0, 0, 255);
        }
      }
    }

    return bw;
  }

  Future<String?> _process(Uint8List jpeg) async {
    try {
      final now = DateTime.now();
      final diff = now.difference(_lastProcessed).inMilliseconds;
      final isRealtime = diff < 300;
      _lastProcessed = now;

      var img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      img = preprocessPlate(img);

      final tmp = await getTemporaryDirectory();
      final file = File(
        p.join(tmp.path, 'ocr_${now.millisecondsSinceEpoch}.jpg'),
      )..writeAsBytesSync(imglib.encodeJpg(img, quality: 100), flush: true);

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

      if (lines.isEmpty) return "";

      String normalize(String raw) {
        var t = raw
            .toUpperCase()
            .replaceAll(RegExp(r'[^A-Z0-9Ø\s\-]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();

        t = t.replaceAll('4', 'A').replaceAll('7', 'T');

        final re = RegExp(r'^([A-Z]{1,3})\s*([A-Z0-9]{1,5})\s*([A-ZØ]{0,4})$');
        final m = re.firstMatch(t);
        if (m == null) return t;

        var prefix = m[1] ?? '';
        var mid = m[2] ?? '';
        var suffix = m[3] ?? '';

        prefix = prefix
            .replaceAll('0', 'O')
            .replaceAll('1', 'I')
            .replaceAll('2', 'Z')
            .replaceAll('3', 'B')
            .replaceAll('5', 'S')
            .replaceAll('6', 'G')
            .replaceAll('8', 'B');

        mid = mid
            .replaceAll('O', '0')
            .replaceAll('Ø', '0')
            .replaceAll('I', '1')
            .replaceAll('Z', '2')
            .replaceAll('T', '7')
            .replaceAll('S', '5')
            .replaceAll('B', '8')
            .replaceAll('G', '6');

        suffix = suffix
            .replaceAll('0', 'O')
            .replaceAll('Ø', 'O')
            .replaceAll('Q', 'O')
            .replaceAll('1', 'I')
            .replaceAll('2', 'Z')
            .replaceAll('5', 'S')
            .replaceAll('6', 'G')
            .replaceAll('8', 'B')
            .replaceAll('3', 'B');

        return "$prefix $mid $suffix".trim();
      }

      final validPrefix = [
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

      final plateRegex = RegExp(r'^[A-Z]{1,3}[\s\-]?\d{1,5}[\s\-]?[A-Z]{0,4}$');

      String? plate;

      for (final raw in lines) {
        final txt = normalize(raw);
        if (plate == null && plateRegex.hasMatch(txt)) {
          final prefix = txt.split(RegExp(r'[\s\-]+')).first;
          if (validPrefix.contains(prefix)) plate = txt;
        }
      }

      if (plate != null) {
        final formatted = plate.replaceAll(RegExp(r'\s+'), ' ').trim();
        debugPrint(
          isRealtime
              ? "📸 [Realtime OCR] $formatted"
              : "🖼️ [Gallery OCR] $formatted",
        );
        return formatted;
      }

      debugPrint("🚫 [Filtered OCR] invalid/low-confidence");
      return "";
    } catch (e, st) {
      debugPrint("❌ OCR error: $e\n$st");
      return null;
    }
  }

  void dispose() {
    _queue.close();
    _onResult.close();
  }
}
