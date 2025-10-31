import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
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

class YoloService {
  final int inputSize;
  final double scoreThreshold;
  final Uint8List modelBytes;
  final String? modelPath;

  YoloService._({
    required this.inputSize,
    required this.scoreThreshold,
    required this.modelBytes,
    required this.modelPath,
  });

  static Future<YoloService> create({
    Uint8List? modelBytes,
    String? modelPath,
    required int inputSize,
    double scoreThreshold = 0.5,
  }) async {
    Uint8List bytes;
    if (modelBytes != null) {
      bytes = modelBytes;
    } else if (modelPath != null) {
      final data = await rootBundle.load(modelPath);
      bytes = data.buffer.asUint8List();
    } else {
      throw ArgumentError('Model path atau bytes harus diberikan');
    }

    return YoloService._(
      inputSize: inputSize,
      scoreThreshold: scoreThreshold,
      modelBytes: bytes,
      modelPath: modelPath,
    );
  }

  Future<List<YoloResult>> detectFromImageBytes(Uint8List jpegBytes) async {
    return compute(_detectOnIsolate, {
      'jpegBytes': jpegBytes,
      'inputSize': inputSize,
      'scoreThreshold': scoreThreshold,
      'modelBytes': modelBytes,
    });
  }
}

Future<List<YoloResult>> _detectOnIsolate(Map<String, dynamic> args) async {
  final jpegBytes = args['jpegBytes'] as Uint8List;
  final modelBytes = args['modelBytes'] as Uint8List;
  final inputSize = args['inputSize'] as int;
  final scoreThreshold = args['scoreThreshold'] as double;

  final options = InterpreterOptions();
  options.addDelegate(XNNPackDelegate());

  final interpreter = Interpreter.fromBuffer(modelBytes, options: options);
  final img = imglib.decodeImage(jpegBytes);
  if (img == null) return [];

  final resized = imglib.copyResize(img, width: inputSize, height: inputSize);
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
  interpreter.close();

  final xs = output[0][0];
  final ys = output[0][1];
  final ws = output[0][2];
  final hs = output[0][3];
  final confs = output[0][4];

  final results = <YoloResult>[];
  for (int i = 0; i < 8400; i++) {
    final score = confs[i];
    if (score < scoreThreshold) continue;
    final x = xs[i];
    final y = ys[i];
    final w = ws[i];
    final h = hs[i];
    results.add(
      YoloResult(
        x1: ((x - w / 2) * inputSize).round(),
        y1: ((y - h / 2) * inputSize).round(),
        x2: ((x + w / 2) * inputSize).round(),
        y2: ((y + h / 2) * inputSize).round(),
        score: score,
        label: 'plate',
      ),
    );
  }
  return results;
}
