import 'dart:typed_data';

class PlateGalleryState {
  final bool isProcessing;
  final double progress;
  final String? message;
  final String? lastText;
  final Uint8List? preview;

  PlateGalleryState({
    required this.isProcessing,
    required this.progress,
    required this.message,
    required this.lastText,
    required this.preview,
  });
}
