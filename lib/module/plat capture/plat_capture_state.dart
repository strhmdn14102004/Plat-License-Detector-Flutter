import 'dart:typed_data';

import 'package:camera/camera.dart';

class PlateCameraCaptureState {
  static const Object _sentinel = Object();
  final bool isReady;
  final bool isProcessing;
  final double progress;
  final String? message;
  final String? lastText;
  final Uint8List? preview;
  final CameraController? controller;
  final double brightness;
  final double contrast;

  const PlateCameraCaptureState({
    required this.isReady,
    required this.isProcessing,
    required this.progress,
    required this.message,
    required this.lastText,
    required this.preview,
    required this.controller,
    required this.brightness,
    required this.contrast,
  });

  factory PlateCameraCaptureState.initial() => const PlateCameraCaptureState(
    isReady: false,
    isProcessing: false,
    progress: 0.0,
    message: 'Menyiapkan kamera...',
    lastText: null,
    preview: null,
    controller: null,
    brightness: 0.05,
    contrast: 1.25,
  );

  PlateCameraCaptureState copyWith({
    bool? isReady,
    bool? isProcessing,
    double? progress,
    Object? message = _sentinel,
    Object? lastText = _sentinel,
    Object? preview = _sentinel,
    Object? controller = _sentinel,
    double? brightness,
    double? contrast,
  }) {
    final String? nextMessage = identical(message, _sentinel)
        ? this.message
        : message as String?;
    final String? nextLastText = identical(lastText, _sentinel)
        ? this.lastText
        : lastText as String?;
    final Uint8List? nextPreview = identical(preview, _sentinel)
        ? this.preview
        : preview as Uint8List?;
    final CameraController? nextController = identical(controller, _sentinel)
        ? this.controller
        : controller as CameraController?;

    return PlateCameraCaptureState(
      isReady: isReady ?? this.isReady,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      message: nextMessage,
      lastText: nextLastText,
      preview: nextPreview,
      controller: nextController,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
    );
  }
}
