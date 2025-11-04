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

  Future<String?> _process(Uint8List jpeg) async {
    try {
      final img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      final tmp = await getTemporaryDirectory();
      final file = File(
        p.join(tmp.path, 'ocr_${DateTime.now().millisecondsSinceEpoch}.jpg'),
      )..writeAsBytesSync(imglib.encodeJpg(img, quality: 90), flush: true);

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

      String normalize(String t) {
        return t
            .replaceAll('8', 'B')
            .replaceAll('0', 'O')
            .replaceAll('1', 'I')
            .replaceAll('2', 'Z')
            .replaceAll(RegExp(r'[^A-Z0-9\s\-]'), ' ')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
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

      final plateRegex = RegExp(
        r'^[A-Z]{1,3}[\s\-]?\d{1,5}[\s\-]?[A-Z]{0,4}$',
        caseSensitive: true,
      );

      final timeRegex = RegExp(r'^\d{2}[:.,]?\d{2}$');

      String? plate;
      String? time;

      for (final raw in lines) {
        final txt = normalize(raw);
        if (plate == null && plateRegex.hasMatch(txt)) {
          final prefix = txt.split(RegExp(r'[\s\-]+')).first;
          if (validPrefix.contains(prefix)) plate = txt;
        } else if (time == null && timeRegex.hasMatch(txt)) {
          time = txt
              .replaceAll(':', '.')
              .replaceAll(',', '.')
              .replaceAll('•', '.');
        }
      }

      if (plate != null) {
        final formatted = plate.replaceAll(RegExp(r'\s+'), ' ').trim();
        return time != null ? '$formatted\n$time' : formatted;
      }

      final fallback = lines.firstWhere(
        (t) => t.contains(RegExp(r'\d')),
        orElse: () => lines.first,
      );
      return normalize(fallback);
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
