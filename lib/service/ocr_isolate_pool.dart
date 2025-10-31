// ignore_for_file: body_might_complete_normally_catch_error

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
      var img = imglib.decodeImage(jpeg);
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
      return lines.take(2).join('\n');
    } catch (_) {
      return null;
    }
  }

  void dispose() {
    _queue.close();
    _onResult.close();
  }
}
