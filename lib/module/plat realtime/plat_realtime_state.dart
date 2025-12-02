import 'dart:typed_data';

import 'package:camera/camera.dart';

class PlateRealtimeState {
  final bool isReady;
  final bool isProcessing;
  final CameraController? controller;
  final String? text;
  final FlashMode flash;
  final Uint8List? cropped;
  final Uint8List? fullFrame;
  final String message;

  const PlateRealtimeState({
    required this.isReady,
    required this.isProcessing,
    required this.controller,
    required this.text,
    required this.flash,
    required this.cropped,
    required this.fullFrame,
    required this.message,
  });

  factory PlateRealtimeState.initial() => const PlateRealtimeState(
    isReady: false,
    isProcessing: false,
    controller: null,
    text: null,
    flash: FlashMode.off,
    cropped: null,
    fullFrame: null,
    message: "Menyiapkan kamera...",
  );
}
