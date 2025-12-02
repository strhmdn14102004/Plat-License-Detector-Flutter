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
  int _nextIndex = 0;
  bool _initialized = false;

  YoloIsolatePool({this.numWorkers = 2});

  /// ---------------------------------------------------------------------------
  /// INIT THE POOL (GPU → CPU fallback)
  /// ---------------------------------------------------------------------------
  Future<void> init(
    Uint8List modelBytes,
    int inputSize,
    double threshold,
  ) async {
    if (_initialized) return;

    for (int i = 0; i < numWorkers; i++) {
      final ready = Completer<void>();
      final rp = ReceivePort();

      final isolate = await Isolate.spawn(_entry, {
        'sendPort': rp.sendPort,
        'modelBytes': modelBytes,
        'inputSize': inputSize,
        'threshold': threshold,
      });

      late SendPort workerSend;
      rp.listen((msg) {
        if (msg is SendPort) {
          workerSend = msg;
          ready.complete();
        } else if (msg is String) {
          debugPrint("🧠 [YOLO isolate $i] $msg");
        }
      });

      await ready.future;
      _workers.add(_YoloWorker(isolate, workerSend));
    }

    _initialized = true;
    debugPrint("✅ YOLO pool ready (${_workers.length} isolates)");
  }

  /// ---------------------------------------------------------------------------
  /// SEND FRAME TO WORKER
  /// ---------------------------------------------------------------------------
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

  /// ---------------------------------------------------------------------------
  /// CLEANUP
  /// ---------------------------------------------------------------------------
  void dispose() {
    for (final w in _workers) {
      w.isolate.kill(priority: Isolate.immediate);
    }
    _workers.clear();
  }

  /// ---------------------------------------------------------------------------
  /// ISOLATE ENTRY
  /// ---------------------------------------------------------------------------
  static void _entry(Map<String, dynamic> args) async {
    final main = args['sendPort'] as SendPort;
    final inputSize = args['inputSize'] as int;
    final threshold = args['threshold'] as double;
    final modelBytes = args['modelBytes'] as Uint8List;

    final port = ReceivePort();
    main.send(port.sendPort);

    Interpreter? interpreter;
    final opts = InterpreterOptions();

    try {
      opts.addDelegate(GpuDelegateV2());
      interpreter = Interpreter.fromBuffer(modelBytes, options: opts);
      main.send("🚀 GPU delegate active");
    } catch (_) {
      try {
        opts.addDelegate(XNNPackDelegate());
        interpreter = Interpreter.fromBuffer(modelBytes, options: opts);
        main.send("⚙️ GPU failed → XNNPack CPU");
      } catch (e) {
        interpreter = Interpreter.fromBuffer(modelBytes);
        main.send("⚠️ Fallback: raw CPU mode ($e)");
      }
    }

    port.listen((msg) {
      if (msg is! Map || !msg.containsKey('jpeg')) return;

      final jpeg = msg['jpeg'] as Uint8List;
      final SendPort reply = msg['reply'];

      final img = imglib.decodeImage(jpeg);
      if (img == null) {
        reply.send([]);
        return;
      }

      final int origW = img.width;
      final int origH = img.height;

      /// LETTERBOXING — keeping aspect ratio
      final double scale = math.min(
        inputSize / origW,
        inputSize / origH,
      ).clamp(0.00001, 1000.0);

      final int resizedW = (origW * scale).round().clamp(1, inputSize);
      final int resizedH = (origH * scale).round().clamp(1, inputSize);

      final imglib.Image canvas = imglib.Image(width: inputSize, height: inputSize);
      final imglib.Image resized = imglib.copyResize(
        img,
        width: resizedW,
        height: resizedH,
        interpolation: imglib.Interpolation.linear,
      );

      final offsetX = ((inputSize - resizedW) / 2).round();
      final offsetY = ((inputSize - resizedH) / 2).round();

      for (int y = 0; y < resized.height; y++) {
        for (int x = 0; x < resized.width; x++) {
          canvas.setPixelRgba(
            offsetX + x,
            offsetY + y,
            resized.getPixel(x, y).r,
            resized.getPixel(x, y).g,
            resized.getPixel(x, y).b,
            255,
          );
        }
      }

      /// PREPARE INPUT
      final input = List<double>.filled(inputSize * inputSize * 3, 0.0);
      int idx = 0;

      for (int y = 0; y < inputSize; y++) {
        for (int x = 0; x < inputSize; x++) {
          final px = canvas.getPixel(x, y);
          input[idx++] = px.r / 255.0;
          input[idx++] = px.g / 255.0;
          input[idx++] = px.b / 255.0;
        }
      }

      /// OUTPUT [1,5,8400]
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

      final double invScale = scale <= 0 ? 1 : 1 / scale;

      final double padX = offsetX.toDouble();
      final double padY = offsetY.toDouble();

      final List<Map<String, dynamic>> detections = [];

      for (int i = 0; i < 8400; i++) {
        final score = confs[i];
        if (score < threshold) continue;

        final cx = xs[i] * inputSize;
        final cy = ys[i] * inputSize;
        final w = ws[i] * inputSize;
        final h = hs[i] * inputSize;

        final x1 = ((cx - w / 2 - padX) * invScale)
            .clamp(0, origW.toDouble());
        final y1 = ((cy - h / 2 - padY) * invScale)
            .clamp(0, origH.toDouble());
        final x2 = ((cx + w / 2 - padX) * invScale)
            .clamp(0, origW.toDouble());
        final y2 = ((cy + h / 2 - padY) * invScale)
            .clamp(0, origH.toDouble());

        if (x2 <= x1 || y2 <= y1) continue;

        detections.add({
          'x1': x1.round(),
          'y1': y1.round(),
          'x2': x2.round(),
          'y2': y2.round(),
          'score': score,
        });
      }

      reply.send(detections);
    });
  }
}
