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
  double marginFactor = 0.25,
}) {
  if (rect.isEmpty) return rect;

  final double mx = (rect.width * marginFactor) / 2;
  final double my = (rect.height * marginFactor) / 2;

  final double left = math.max(0, rect.left - mx);
  final double top = math.max(0, rect.top - my);
  final double right = math.min(bounds.width, rect.right + mx);
  final double bottom = math.min(bounds.height, rect.bottom + my);

  return Rect.fromLTRB(left, top, right, bottom);
}

Future<String> waitHybridOcr(
  OcrIsolatePool ocr, {
  required Uint8List cropped,
  required Uint8List fullImage,
  Duration timeout = const Duration(seconds: 7),
}) async {
  String? crop = await _waitForSingleOcr(ocr, cropped, timeout);
  if (crop != null && crop.length >= 5) return crop;

  debugPrint("🔁 Fallback ke OCR full image...");
  String? full = await _waitForSingleOcr(ocr, fullImage, timeout);

  return full ?? "";
}

Future<String?> _waitForSingleOcr(
  OcrIsolatePool ocr,
  Uint8List img,
  Duration timeout,
) async {
  String best = "";
  final completer = Completer<void>();
  Timer? timer;

  final sub = ocr.results.listen((text) {
    if (text.isEmpty) return;
    best = text;
    if (best.length >= 6 && !completer.isCompleted) {
      completer.complete();
    }
  });

  ocr.pushCrop(img);

  timer = Timer(timeout, () {
    if (!completer.isCompleted) completer.complete();
  });

  await completer.future;
  await sub.cancel();
  timer.cancel();

  return best.trim();
}

Future<Uint8List?> cropPlateRegion(
  Uint8List jpeg,
  Rect rect, {
  double marginFactor = 0.22,
  int quality = 100,
}) async {
  return compute(_cropPlateSync, {
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

Uint8List? _cropPlateSync(Map<String, dynamic> args) {
  try {
    final jpeg = args['jpeg'] as Uint8List;
    final Float64List data = args['rect'];
    final double margin = args['margin'] ?? 0.2;
    final int quality = args['quality'] ?? 100;

    final imglib.Image? img = imglib.decodeImage(jpeg);
    if (img == null) return null;

    Rect raw = Rect.fromLTRB(data[0], data[1], data[2], data[3]);

    Rect expanded = expandRectWithinBounds(
      raw,
      Size(img.width.toDouble(), img.height.toDouble()),
      marginFactor: margin,
    );

    final int x = expanded.left.floor().clamp(0, img.width - 1);
    final int y = expanded.top.floor().clamp(0, img.height - 1);
    final int w = expanded.width.ceil().clamp(1, img.width - x);
    final int h = expanded.height.ceil().clamp(1, img.height - y);

    final cropped = imglib.copyCrop(img, x: x, y: y, width: w, height: h);

    return Uint8List.fromList(imglib.encodeJpg(cropped, quality: quality));
  } catch (e) {
    debugPrint("❌ crop error: $e");
    return null;
  }
}
