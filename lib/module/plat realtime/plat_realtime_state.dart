import 'dart:ui';

import 'package:camera/camera.dart';

class PlateRealtimeState {
  final bool isCameraReady;
  final CameraController? controller;
  final bool isProcessing;
  final Rect? lastBox;
  final String? lastText;
  final List<String> detected;
  final String? message;

  PlateRealtimeState({
    required this.isCameraReady,
    required this.controller,
    required this.isProcessing,
    required this.lastBox,
    required this.lastText,
    required this.detected,
    required this.message,
  });
}
