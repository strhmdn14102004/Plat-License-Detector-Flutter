import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:face_recognition/service/ocr_isolate_pool.dart';

const int kYoloInputSize = 640;

Rect expandRectWithinBounds(
  Rect rect,
  Size bounds, {
  double marginFactor = 0.2,
}) {
  if (rect.isEmpty) return rect;

  final double mx = rect.width * marginFactor / 2;
  final double my = rect.height * marginFactor / 2;

  final double left = math.max(0, rect.left - mx);
  final double top = math.max(0, rect.top - my);
  final double right = math.min(bounds.width, rect.right + mx);
  final double bottom = math.min(bounds.height, rect.bottom + my);

  return Rect.fromLTRB(left, top, right, bottom);
}

Future<String> waitForOcrResult(
  OcrIsolatePool ocr,
  Uint8List image, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  String bestText = '';
  final completer = Completer<void>();
  Timer? timer;

  final subscription = ocr.results.listen((text) {
    if (text.isEmpty) return;
    if (text.length > bestText.length) {
      bestText = text;
      if (bestText.length >= 6 && !completer.isCompleted) {
        completer.complete();
      }
    }
  });

  ocr.push(image);

  timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete();
  });

  await completer.future;
  await subscription.cancel();
  timer?.cancel();

  return bestText.trim();
}
