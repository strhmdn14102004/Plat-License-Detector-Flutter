import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;
import 'package:tflite_flutter/tflite_flutter.dart';

class YoloResult {
  final int x1, y1, x2, y2;
  final double score;
  final String label;
  YoloResult({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.score,
    required this.label,
  });
}

class YoloIsolatePool {
  late Isolate _isolate;
  late SendPort _sendPort;
  final _receivePort = ReceivePort();
  bool _initialized = false;

  Future<void> init(
    Uint8List modelBytes,
    int inputSize,
    double threshold,
  ) async {
    if (_initialized) return;
    final ready = Completer<void>();
    _isolate = await Isolate.spawn(_entry, {
      'sendPort': _receivePort.sendPort,
      'modelBytes': modelBytes,
      'inputSize': inputSize,
      'threshold': threshold,
    });
    _receivePort.listen((msg) {
      if (msg is SendPort) {
        _sendPort = msg;
        _initialized = true;
        ready.complete();
      }
    });
    await ready.future;
  }

  Future<List<YoloResult>> detect(Uint8List jpegBytes) async {
    if (!_initialized) return [];
    final rp = ReceivePort();
    _sendPort.send({'jpeg': jpegBytes, 'reply': rp.sendPort});
    final res = await rp.first;
    rp.close();
    return (res as List)
        .map(
          (r) => YoloResult(
            x1: r['x1'],
            y1: r['y1'],
            x2: r['x2'],
            y2: r['y2'],
            score: r['score'],
            label: 'plate',
          ),
        )
        .toList();
  }

  void dispose() {
    _isolate.kill(priority: Isolate.immediate);
    _receivePort.close();
  }

  static void _entry(Map<String, dynamic> args) {
    final mainSendPort = args['sendPort'] as SendPort;
    final inputSize = args['inputSize'] as int;
    final threshold = args['threshold'] as double;
    final modelBytes = args['modelBytes'] as Uint8List;

    final options = InterpreterOptions()..addDelegate(XNNPackDelegate());
    final interpreter = Interpreter.fromBuffer(modelBytes, options: options);

    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    port.listen((msg) {
      if (msg is Map && msg.containsKey('jpeg')) {
        final jpeg = msg['jpeg'] as Uint8List;
        final reply = msg['reply'] as SendPort;
        final img = imglib.decodeImage(jpeg);
        if (img == null) {
          reply.send([]);
          return;
        }

        final resized = imglib.copyResize(
          img,
          width: inputSize,
          height: inputSize,
        );
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

        final xs = output[0][0];
        final ys = output[0][1];
        final ws = output[0][2];
        final hs = output[0][3];
        final confs = output[0][4];

        final results = <Map<String, dynamic>>[];
        for (int i = 0; i < 8400; i++) {
          final score = confs[i];
          if (score < threshold) continue;
          final x = xs[i];
          final y = ys[i];
          final w = ws[i];
          final h = hs[i];
          results.add({
            'x1': ((x - w / 2) * inputSize).round(),
            'y1': ((y - h / 2) * inputSize).round(),
            'x2': ((x + w / 2) * inputSize).round(),
            'y2': ((y + h / 2) * inputSize).round(),
            'score': score,
          });
        }
        reply.send(results);
      }
    });
  }
}
