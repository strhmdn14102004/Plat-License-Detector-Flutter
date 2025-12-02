import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;
import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';

const int kYoloInputSize = 640;

Rect expandRectWithinBounds(
  Rect rect,
  Size bounds, {
  double marginFactor = 0.15,
}) {
  if (rect.isEmpty) return rect;

  final mx = rect.width * marginFactor / 2;
  final my = rect.height * marginFactor / 2;

  return Rect.fromLTRB(
    math.max(0, rect.left - mx),
    math.max(0, rect.top - my),
    math.min(bounds.width, rect.right + mx),
    math.min(bounds.height, rect.bottom + my),
  );
}

int scoreText(String s) {
  final upper = s.toUpperCase();

  int digits = RegExp(r'\d').allMatches(upper).length * 3;
  int letters = RegExp(r'[A-Z]').allMatches(upper).length;
  int prefixBonus = RegExp(r'^[A-Z]{1,3}').hasMatch(upper) ? 5 : 0;

  return digits + letters + prefixBonus;
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

    if (scoreText(text) > scoreText(bestText)) {
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
  timer.cancel();

  return bestText.trim();
}

Future<Uint8List?> cropPlateRegion(
  Uint8List jpeg,
  Rect rect, {
  double marginFactor = 0.15,
  int quality = 100,
}) async {
  return compute(_cropPlateRegion, {
    'jpeg': jpeg,
    'rect': Float64List.fromList([
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
    ]),
    'margin': marginFactor,
    'quality': quality,
  });
}

Uint8List? cropPlateRegionSync(
  Uint8List jpeg,
  Rect rect, {
  double marginFactor = 0.15,
  int quality = 100,
}) {
  return _cropPlateRegion({
    'jpeg': jpeg,
    'rect': Float64List.fromList([
      rect.left,
      rect.top,
      rect.right,
      rect.bottom,
    ]),
    'margin': marginFactor,
    'quality': quality,
  });
}

Uint8List? _cropPlateRegion(Map<String, dynamic> args) {
  try {
    final jpeg = args['jpeg'] as Uint8List;
    final Float64List data = args['rect'] as Float64List;
    final double margin = (args['margin'] as double?) ?? 0.15;
    final int quality = (args['quality'] as int?) ?? 100;

    final imglib.Image? img = imglib.decodeImage(jpeg);
    if (img == null) return null;

    final rawRect = Rect.fromLTRB(data[0], data[1], data[2], data[3]);

    final Rect scaledRect = expandRectWithinBounds(
      rawRect,
      Size(img.width.toDouble(), img.height.toDouble()),
      marginFactor: margin,
    );

    final int x = scaledRect.left.floor().clamp(0, img.width - 1);
    final int y = scaledRect.top.floor().clamp(0, img.height - 1);
    final int w = scaledRect.width.ceil().clamp(1, img.width - x);
    final int h = scaledRect.height.ceil().clamp(1, img.height - y);

    var cropped = imglib.copyCrop(img, x: x, y: y, width: w, height: h);

    final thumb = imglib.copyResize(cropped, width: 40);
    final gray = thumb.getBytes().map((b) => b & 0xFF).toList();
    final meanGray = gray.reduce((a, b) => a + b) / gray.length;

    bool isBlackPlate = meanGray < 90;
    bool isBrightPlate = meanGray > 170;

    if (isBlackPlate) {
      cropped = imglib.adjustColor(cropped, brightness: 0.35, contrast: 1.45);
    } else if (isBrightPlate) {
      cropped = imglib.adjustColor(cropped, brightness: -0.10, contrast: 1.20);
    } else {
      cropped = imglib.adjustColor(cropped, brightness: 0.10, contrast: 1.25);
    }

    cropped = imglib.convolution(
      cropped,
      filter: const [0, -1, 0, -1, 4, -1, 0, -1, 0],
      div: 1,
      offset: 0,
    );

    cropped = imglib.gaussianBlur(cropped, radius: 1);

    return Uint8List.fromList(imglib.encodeJpg(cropped, quality: quality));
  } catch (e) {
    debugPrint("❌ cropPlateRegion error: $e");
    return null;
  }
}
