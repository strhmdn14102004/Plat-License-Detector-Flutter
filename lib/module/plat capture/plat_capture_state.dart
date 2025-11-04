import 'dart:ui';

import 'package:camera/camera.dart';

class PlateCaptureState {
  final bool isCameraReady;
  final CameraController? controller;
  final bool isProcessing;
  final Rect? lastBox;
  final String? lastText;
  final String? message;

  PlateCaptureState({
    required this.isCameraReady,
    required this.controller,
    required this.isProcessing,
    required this.lastBox,
    required this.lastText,
    required this.message,
  });
}
