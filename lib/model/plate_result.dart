class PlateResult {
  final String plateNumber;
  final String fullText;
  final DateTime timestamp;
  final String imagePath;
  final String? croppedImagePath;

  PlateResult({
    required this.plateNumber,
    required this.fullText,
    required this.timestamp,
    required this.imagePath,
    this.croppedImagePath,
  });
}
