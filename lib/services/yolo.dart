import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

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
  int _roundIndex = 0;
  bool _initialized = false;

  YoloIsolatePool({this.numWorkers = 2});

  Future<void> init(Uint8List model, int inputSize, double threshold) async {
    if (_initialized) return;

    for (int i = 0; i < numWorkers; i++) {
      final ready = Completer<void>();
      final receive = ReceivePort();

      final isolate = await Isolate.spawn(_entry, {
        "sendPort": receive.sendPort,
        "modelBytes": model,
        "inputSize": inputSize,
        "threshold": threshold,
      });

      late SendPort sp;
      receive.listen((msg) {
        if (msg is SendPort) {
          sp = msg;
          ready.complete();
        }
      });

      await ready.future;
      _workers.add(_YoloWorker(isolate, sp));
    }

    _initialized = true;
  }

  Future<List<YoloResult>> detect(Uint8List jpeg) async {
    if (!_initialized) return [];

    final worker = _workers[_roundIndex];
    _roundIndex = (_roundIndex + 1) % _workers.length;

    final rp = ReceivePort();
    worker.sendPort.send({"jpeg": jpeg, "reply": rp.sendPort});

    final result = await rp.first as List;
    rp.close();

    return result
        .map(
          (r) => YoloResult(
            x1: r["x1"],
            y1: r["y1"],
            x2: r["x2"],
            y2: r["y2"],
            score: r["score"],
            label: "plate",
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
    final mainPort = args["sendPort"] as SendPort;
    final inputSize = args["inputSize"] as int;
    final threshold = args["threshold"] as double;
    final modelBytes = args["modelBytes"] as Uint8List;

    final port = ReceivePort();
    mainPort.send(port.sendPort);

    Interpreter? interpreter;
    final opts = InterpreterOptions();

    try {
      opts.addDelegate(GpuDelegateV2());
      interpreter = Interpreter.fromBuffer(modelBytes, options: opts);
    } catch (_) {
      opts.addDelegate(XNNPackDelegate());
      interpreter = Interpreter.fromBuffer(modelBytes, options: opts);
    }

    port.listen((msg) {
      if (msg is Map && msg.containsKey("jpeg")) {
        final jpeg = msg["jpeg"] as Uint8List;
        final reply = msg["reply"] as SendPort;

        final img = imglib.decodeImage(jpeg);
        if (img == null) {
          reply.send([]);
          return;
        }

        final originalW = img.width;
        final originalH = img.height;

        final scale = math.min(inputSize / originalW, inputSize / originalH);

        final rw = (originalW * scale).round().clamp(1, inputSize);
        final rh = (originalH * scale).round().clamp(1, inputSize);

        final ox = ((inputSize - rw) / 2).round();
        final oy = ((inputSize - rh) / 2).round();

        final letter = imglib.Image(width: inputSize, height: inputSize);
        final resized = imglib.copyResize(img, width: rw, height: rh);

        for (int y = 0; y < rh; y++) {
          for (int x = 0; x < rw; x++) {
            final px = resized.getPixel(x, y);
            letter.setPixelRgba(ox + x, oy + y, px.r, px.g, px.b, px.a);
          }
        }

        final input = List<double>.filled(inputSize * inputSize * 3, 0.0);
        int idx = 0;

        for (int y = 0; y < inputSize; y++) {
          for (int x = 0; x < inputSize; x++) {
            final px = letter.getPixel(x, y);
            input[idx++] = px.r / 255;
            input[idx++] = px.g / 255;
            input[idx++] = px.b / 255;
          }
        }

        final out = List.generate(
          1,
          (_) => List.generate(5, (_) => List<double>.filled(8400, 0.0)),
        );

        interpreter!.run(input.reshape([1, inputSize, inputSize, 3]), out);

        final xs = out[0][0];
        final ys = out[0][1];
        final ws = out[0][2];
        final hs = out[0][3];
        final conf = out[0][4];

        final invScale = 1 / scale;
        final results = <Map<String, dynamic>>[];

        for (int i = 0; i < 8400; i++) {
          if (conf[i] < threshold) continue;

          final x = xs[i];
          final y = ys[i];
          final w = ws[i];
          final h = hs[i];

          final rx1 = (x - w / 2) * inputSize;
          final ry1 = (y - h / 2) * inputSize;
          final rx2 = (x + w / 2) * inputSize;
          final ry2 = (y + h / 2) * inputSize;

          final ax1 = ((rx1 - ox) * invScale).clamp(0, originalW.toDouble());
          final ay1 = ((ry1 - oy) * invScale).clamp(0, originalH.toDouble());
          final ax2 = ((rx2 - ox) * invScale).clamp(0, originalW.toDouble());
          final ay2 = ((ry2 - oy) * invScale).clamp(0, originalH.toDouble());

          if (ax2 <= ax1 || ay2 <= ay1) continue;

          results.add({
            "x1": ax1.round(),
            "y1": ay1.round(),
            "x2": ax2.round(),
            "y2": ay2.round(),
            "score": conf[i],
          });
        }

        reply.send(results);
      }
    });
  }
}
