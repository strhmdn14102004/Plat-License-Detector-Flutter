// ignore_for_file: body_might_complete_normally_catch_error

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart';

class OcrIsolatePool {
  final _queue = StreamController<Uint8List>();
  bool _running = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  final _recognizer = _PaddleOcrRecognizer();

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
      final now = DateTime.now();
      final diff = now.difference(_lastProcessed).inMilliseconds;
      final isRealtime = diff < 300;
      _lastProcessed = now;

      var img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      if (isRealtime) {
        img = imglib.adjustColor(img, brightness: 0.05, contrast: 1.15);
        img = imglib.gaussianBlur(img, radius: 1);
      }

      final lines = await _recognizer.recognize(img);

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

        var combined = '$prefix $mid $suffix'.trim();
        return combined.replaceAll(RegExp(r'\s+'), ' ').trim();
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
      final plateWithTimeRegex = RegExp(
        r'^([A-Z]{1,3}\s?\d{1,5}\s?[A-Z]{0,4})[\s\n]+(\d{2}[:.,-]?\d{2})$',
      );

      String? plate;

      for (final raw in lines) {
        final txt = normalize(raw);
        if (plate == null && plateRegex.hasMatch(txt)) {
          final prefix = txt.split(RegExp(r'[\s\-]+')).first;
          if (validPrefix.contains(prefix)) plate = txt;
        }
      }

      if (plate == null) {
        for (int i = 0; i < lines.length - 1; i++) {
          final combined = "${normalize(lines[i])}\n${normalize(lines[i + 1])}";
          if (plateWithTimeRegex.hasMatch(combined)) {
            final prefix = combined.split(RegExp(r'[\s\-]+')).first;
            if (validPrefix.contains(prefix)) {
              plate = combined;
              break;
            }
          }
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

      debugPrint("🚫 [Filtered OCR] ignored invalid or low-confidence text");
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

class _PaddleOcrRecognizer {
  static const int _inputWidth = 320;
  static const int _inputHeight = 48;
  static const int _outputSeqLen = 40;

  static const List<String> _charset = [
    ' ',
    '!',
    '"',
    '#',
    '\$',
    '%',
    '&',
    "'",
    '(',
    ')',
    '*',
    '+',
    ',',
    '-',
    '.',
    '/',
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    ':',
    ';',
    '<',
    '=',
    '>',
    '?',
    '@',
    'A',
    'B',
    'C',
    'D',
    'E',
    'F',
    'G',
    'H',
    'I',
    'J',
    'K',
    'L',
    'M',
    'N',
    'O',
    'P',
    'Q',
    'R',
    'S',
    'T',
    'U',
    'V',
    'W',
    'X',
    'Y',
    'Z',
    '[',
    '\\',
    ']',
    '^',
    '_',
    '`',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n',
    'o',
    'p',
    'q',
    'r',
    's',
    't',
    'u',
    'v',
    'w',
    'x',
    'y',
    'z',
    '{',
    '|',
    '}',
    '~',
    '§',
  ];

  Interpreter? _interpreter;

  Future<void> _ensureInterpreter() async {
    _interpreter ??= await Interpreter.fromAsset(
      'assets/models/rec_model_float16.tflite',
      options: InterpreterOptions()..threads = 2,
    );
  }

  Future<List<String>> recognize(imglib.Image image) async {
    await _ensureInterpreter();

    final preprocessed = _preprocess(image);
    final output = List.generate(
      1,
      (_) =>
          List.generate(_outputSeqLen, (_) => List.filled(_charset.length + 1, 0.0)),
    );

    _interpreter!.run(preprocessed, output);

    final decoded = _decode(output[0]);
    return decoded.isEmpty ? <String>[] : [decoded];
  }

  List<List<List<List<double>>>> _preprocess(imglib.Image image) {
    final resized = imglib.copyResize(
      image,
      width: _inputWidth,
      height: _inputHeight,
      interpolation: imglib.Interpolation.average,
    );

    final input = List.generate(
      1,
      (_) => List.generate(
        _inputHeight,
        (y) => List.generate(
          _inputWidth,
          (x) {
            final pixel = resized.getPixel(x, y);
            final r = imglib.getRed(pixel) / 255.0;
            final g = imglib.getGreen(pixel) / 255.0;
            final b = imglib.getBlue(pixel) / 255.0;
            return [r, g, b];
          },
        ),
      ),
    );

    return input;
  }

  String _decode(List<List<double>> logits) {
    if (logits.isEmpty) return '';
    final blankIndex = logits.first.length - 1;
    final buffer = StringBuffer();
    int prev = -1;

    for (final timestep in logits) {
      var maxIndex = 0;
      var maxScore = timestep[0];
      for (int i = 1; i < timestep.length; i++) {
        if (timestep[i] > maxScore) {
          maxScore = timestep[i];
          maxIndex = i;
        }
      }

      if (maxIndex == blankIndex || maxIndex == prev) continue;
      prev = maxIndex;

      if (maxIndex < _charset.length) {
        buffer.write(_charset[maxIndex]);
      } else {
        buffer.write('?');
      }
    }

    return buffer.toString().trim().toUpperCase();
  }
}
