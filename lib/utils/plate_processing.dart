import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as imglib;
import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';

class DeskewResult {
  final Uint8List image;
  final double angle;

  const DeskewResult({required this.image, required this.angle});
}

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
  int quality = 100
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
    final double margin = (args['margin'] as double?) ?? 0.0;
    final int quality = (args['quality'] as int?) ?? 100;

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

Future<DeskewResult?> deskewPlate(
  Uint8List jpeg, {
  double maxAngleDegrees = 12,
  int quality = 100,
}) async {
  return compute(_deskewPlate, {
    'jpeg': jpeg,
    'maxAngle': maxAngleDegrees,
    'quality': quality,
  });
}

DeskewResult? _deskewPlate(Map<String, dynamic> args) {
  try {
    final Uint8List jpeg = args['jpeg'] as Uint8List;
    final double maxAngle = (args['maxAngle'] as double?) ?? 12.0;
    final int quality = (args['quality'] as int?) ?? 100;

    final imglib.Image? decoded = imglib.decodeImage(jpeg);
    if (decoded == null) return null;

    final imglib.Image working = decoded.width > 900
        ? imglib.copyResize(decoded, width: 900)
        : decoded.clone();

    final double angle = _estimateSkewAngle(working, maxAngleDegrees: maxAngle);
    if (angle.abs() < 0.4) {
      return DeskewResult(image: jpeg, angle: 0);
    }

    final imglib.Image rotated = imglib.copyRotate(
      decoded,
      angle: -angle,
    );

    return DeskewResult(
      image: Uint8List.fromList(imglib.encodeJpg(rotated, quality: quality)),
      angle: angle,
    );
  } catch (e) {
    debugPrint('❌ deskewPlate error: $e');
    return null;
  }
}

double _estimateSkewAngle(
  imglib.Image source, {
  double maxAngleDegrees = 12,
}) {
  final imglib.Image gray = imglib.grayscale(source);

  final int width = gray.width;
  final int height = gray.height;
  if (width < 3 || height < 3) return 0;

  double weightedAngle = 0;
  double weightSum = 0;

  for (int y = 1; y < height - 1; y++) {
    for (int x = 1; x < width - 1; x++) {
      final int gx =
          (-imglib.getLuminance(gray.getPixel(x - 1, y - 1))) +
              (imglib.getLuminance(gray.getPixel(x + 1, y - 1))) +
              (-2 * imglib.getLuminance(gray.getPixel(x - 1, y))) +
              (2 * imglib.getLuminance(gray.getPixel(x + 1, y))) +
              (-imglib.getLuminance(gray.getPixel(x - 1, y + 1))) +
              (imglib.getLuminance(gray.getPixel(x + 1, y + 1)));

      final int gy =
          (-imglib.getLuminance(gray.getPixel(x - 1, y - 1))) +
              (-2 * imglib.getLuminance(gray.getPixel(x, y - 1))) +
              (-imglib.getLuminance(gray.getPixel(x + 1, y - 1))) +
              (imglib.getLuminance(gray.getPixel(x - 1, y + 1))) +
              (2 * imglib.getLuminance(gray.getPixel(x, y + 1))) +
              (imglib.getLuminance(gray.getPixel(x + 1, y + 1)));

      final double magnitude = math.sqrt((gx * gx + gy * gy).toDouble());
      if (magnitude < 30) continue;

      final double angle = math.atan2(gy.toDouble(), gx.toDouble()) * 180 / math.pi;
      if (angle.abs() > maxAngleDegrees) continue;

      weightedAngle += angle * magnitude;
      weightSum += magnitude;
    }
  }

  if (weightSum == 0) return 0;
  return weightedAngle / weightSum;
}

