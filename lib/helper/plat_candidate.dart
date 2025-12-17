import 'dart:ui';

class PlateCandidate {
  final String plateNumber;
  final double confidence;
  final Rect? boundingBox;
  final String source;

  PlateCandidate({
    required this.plateNumber,
    required this.confidence,
    this.boundingBox,
    required this.source,
  });
}
