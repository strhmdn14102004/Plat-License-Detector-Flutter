import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
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

class _YoloWorker {
  final Isolate isolate;
  final SendPort sendPort;
  _YoloWorker(this.isolate, this.sendPort);
}

class YoloIsolatePool {
  final int numWorkers;
  final List<_YoloWorker> _workers = [];
  int _nextIndex = 0;
  bool _initialized = false;

  YoloIsolatePool({this.numWorkers = 2});

  Future<void> init(
    Uint8List modelBytes,
    int inputSize,
    double threshold,
  ) async {
    if (_initialized) return;

    for (int i = 0; i < numWorkers; i++) {
      final ready = Completer<void>();
      final receive = ReceivePort();

      final isolate = await Isolate.spawn(_entry, {
        'sendPort': receive.sendPort,
        'modelBytes': modelBytes,
        'inputSize': inputSize,
        'threshold': threshold,
      });

      late SendPort sendPort;
      receive.listen((msg) {
        if (msg is SendPort) {
          sendPort = msg;
          ready.complete();
        } else if (msg is String) {
          debugPrint('🧠 YOLO isolate[$i]: $msg');
        }
      });

      await ready.future;
      _workers.add(_YoloWorker(isolate, sendPort));
    }

    _initialized = true;
    debugPrint("✅ YOLO dual pool ready (${_workers.length} isolates)");
  }

  Future<List<YoloResult>> detect(Uint8List jpegBytes) async {
    if (!_initialized || _workers.isEmpty) return [];
    final worker = _workers[_nextIndex];
    _nextIndex = (_nextIndex + 1) % _workers.length;

    final rp = ReceivePort();
    worker.sendPort.send({'jpeg': jpegBytes, 'reply': rp.sendPort});
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
    for (final w in _workers) {
      w.isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
  }

  static void _entry(Map<String, dynamic> args) {
    final mainSendPort = args['sendPort'] as SendPort;
    final inputSize = args['inputSize'] as int;
    final threshold = args['threshold'] as double;
    final modelBytes = args['modelBytes'] as Uint8List;

    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    Interpreter? interpreter;
    final options = InterpreterOptions();

    try {
      options.addDelegate(GpuDelegateV2());
      interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      mainSendPort.send('✅ GPU delegate active');
    } catch (e) {
      options.addDelegate(XNNPackDelegate());
      interpreter = Interpreter.fromBuffer(modelBytes, options: options);
      mainSendPort.send('⚙️ GPU failed, fallback CPU');
    }

    port.listen((msg) {
      if (msg is Map && msg.containsKey('jpeg')) {
        final jpeg = msg['jpeg'] as Uint8List;
        final reply = msg['reply'] as SendPort;

        final img = imglib.decodeImage(jpeg);
        if (img == null) {
          reply.send([]);
          return;
        }

        final int originalWidth = img.width;
        final int originalHeight = img.height;
        final double scale = math.min(
          inputSize / originalWidth,
          inputSize / originalHeight,
        );
        final int resizedWidth = math.max(1, (originalWidth * scale).round());
        final int resizedHeight = math.max(1, (originalHeight * scale).round());
        final int offsetX = ((inputSize - resizedWidth) / 2).round();
        final int offsetY = ((inputSize - resizedHeight) / 2).round();

        final imglib.Image letterbox = imglib.Image(width: inputSize, height: inputSize);
        final imglib.Image resized = imglib.copyResize(
          img,
          width: resizedWidth,
          height: resizedHeight,
          interpolation: imglib.Interpolation.linear,
        );
        for (int y = 0; y < resized.height; y++) {
          for (int x = 0; x < resized.width; x++) {
            final pixel = resized.getPixel(x, y);
            letterbox.setPixelRgba(
              offsetX + x,
              offsetY + y,
              pixel.r,
              pixel.g,
              pixel.b,
              pixel.a,
            );
          }
        }

        final input = List<double>.filled(inputSize * inputSize * 3, 0.0);
        int index = 0;
        for (int y = 0; y < inputSize; y++) {
          for (int x = 0; x < inputSize; x++) {
            final pixel = letterbox.getPixel(x, y);
            input[index++] = pixel.r / 255.0;
            input[index++] = pixel.g / 255.0;
            input[index++] = pixel.b / 255.0;
          }
        }

        final output = List.generate(
          1,
          (_) => List.generate(5, (_) => List<double>.filled(8400, 0.0)),
        );
        interpreter!.run(input.reshape([1, inputSize, inputSize, 3]), output);

        final xs = output[0][0];
        final ys = output[0][1];
        final ws = output[0][2];
        final hs = output[0][3];
        final confs = output[0][4];

        final double invScale = scale == 0 ? 1.0 : 1.0 / scale;
        final double padX = offsetX.toDouble();
        final double padY = offsetY.toDouble();
        final results = <Map<String, dynamic>>[];
        for (int i = 0; i < 8400; i++) {
          final score = confs[i];
          if (score < threshold) continue;
          final x = xs[i];
          final y = ys[i];
          final w = ws[i];
          final h = hs[i];
          final double rawX1 = (x - w / 2) * inputSize;
          final double rawY1 = (y - h / 2) * inputSize;
          final double rawX2 = (x + w / 2) * inputSize;
          final double rawY2 = (y + h / 2) * inputSize;

          final double mappedX1 = ((rawX1 - padX) * invScale)
              .clamp(0, originalWidth.toDouble());
          final double mappedY1 = ((rawY1 - padY) * invScale)
              .clamp(0, originalHeight.toDouble());
          final double mappedX2 = ((rawX2 - padX) * invScale)
              .clamp(0, originalWidth.toDouble());
          final double mappedY2 = ((rawY2 - padY) * invScale)
              .clamp(0, originalHeight.toDouble());

          if (mappedX2 <= mappedX1 || mappedY2 <= mappedY1) continue;

          results.add({
            'x1': mappedX1.round(),
            'y1': mappedY1.round(),
            'x2': mappedX2.round(),
            'y2': mappedY2.round(),
            'score': score,
          });
        }

        reply.send(results);
      }
    });
  }
}
