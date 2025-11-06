import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;

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
  timer.cancel();

  return bestText.trim();
}

Future<Uint8List?> cropPlateRegion(
  Uint8List jpeg,
  Rect rect, {
  double marginFactor = 0.2,
  int quality = 95,
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
  double marginFactor = 0.2,
  int quality = 95,
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
    final double margin = (args['margin'] as double?) ?? 0.0;
    final int quality = (args['quality'] as int?) ?? 95;

    final imglib.Image? img = imglib.decodeImage(jpeg);
    if (img == null) return null;

    final Rect rawRect = Rect.fromLTRB(data[0], data[1], data[2], data[3]);

    final Rect scaledRect = expandRectWithinBounds(
      rawRect,
      Size(img.width.toDouble(), img.height.toDouble()),
      marginFactor: margin,
    );

    final int x = scaledRect.left.floor().clamp(0, img.width - 1);
    final int y = scaledRect.top.floor().clamp(0, img.height - 1);
    final int w = scaledRect.width.ceil().clamp(1, img.width - x);
    final int h = scaledRect.height.ceil().clamp(1, img.height - y);

    final imglib.Image cropped = imglib.copyCrop(
      img,
      x: x,
      y: y,
      width: w,
      height: h,
    );

    return Uint8List.fromList(imglib.encodeJpg(cropped, quality: quality));
  } catch (e) {
    debugPrint('❌ cropPlateRegion error: $e');
    return null;
  }
}
