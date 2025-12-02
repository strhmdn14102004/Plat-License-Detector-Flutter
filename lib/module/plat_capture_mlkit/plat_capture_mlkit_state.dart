import 'dart:typed_data';

import 'package:camera/camera.dart';

class PlateMlkitCaptureState {
  static const Object _s = Object();

  final bool isReady;
  final bool isProcessing;
  final double progress;
  final String? message;
  final String? lastText;
  final Uint8List? preview;
  final CameraController? controller;
  final FlashMode flashMode;

  const PlateMlkitCaptureState({
    required this.isReady,
    required this.isProcessing,
    required this.progress,
    required this.message,
    required this.lastText,
    required this.preview,
    required this.controller,
    required this.flashMode,
  });

  factory PlateMlkitCaptureState.initial() => const PlateMlkitCaptureState(
    isReady: false,
    isProcessing: false,
    progress: 0.0,
    message: "Menyiapkan kamera...",
    lastText: null,
    preview: null,
    controller: null,
    flashMode: FlashMode.off,
  );

  PlateMlkitCaptureState copyWith({
    bool? isReady,
    bool? isProcessing,
    double? progress,
    Object? message = _s,
    Object? lastText = _s,
    Object? preview = _s,
    Object? controller = _s,
    FlashMode? flashMode,
  }) {
    return PlateMlkitCaptureState(
      isReady: isReady ?? this.isReady,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      message: identical(message, _s) ? this.message : message as String?,
      lastText: identical(lastText, _s) ? this.lastText : lastText as String?,
      preview: identical(preview, _s) ? this.preview : preview as Uint8List?,
      controller: identical(controller, _s)
          ? this.controller
          : controller as CameraController?,
      flashMode: flashMode ?? this.flashMode,
    );
  }
}
