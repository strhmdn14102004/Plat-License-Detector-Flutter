import 'dart:typed_data';

import 'package:camera/camera.dart';

class PlateCameraCaptureState {
  final bool isReady;
  final bool isProcessing;
  final double progress;
  final String? message;
  final String? lastText;
  final Uint8List? preview;
  final CameraController? controller;

  PlateCameraCaptureState({
    required this.isReady,
    required this.isProcessing,
    required this.progress,
    required this.message,
    required this.lastText,
    required this.preview,
    required this.controller,
  });
}
