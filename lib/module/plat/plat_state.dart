import 'dart:ui';

import 'package:camera/camera.dart';

class PlateState {
  final bool isCameraReady;
  final CameraController? controller;
  final bool isProcessing;
  final Rect? lastBox;
  final String? lastText;
  final List<String> detectedPlates;
  final String? message;
  PlateState({
    required this.isCameraReady,
    required this.controller,
    required this.isProcessing,
    required this.lastBox,
    required this.lastText,
    required this.detectedPlates,
    required this.message,
  });
}
