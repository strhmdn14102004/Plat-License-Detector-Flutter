import 'dart:typed_data';

import 'package:camera/camera.dart';

class PlateCameraCaptureZoomState {
  static const Object _sentinel = Object();

  final bool isReady;
  final bool isProcessing;
  final double progress;
  final double currentZoom;
  final String? message;
  final String? lastText;
  final Uint8List? preview;
  final CameraController? controller;

  const PlateCameraCaptureZoomState({
    required this.isReady,
    required this.isProcessing,
    required this.progress,
    required this.message,
    required this.lastText,
    required this.preview,
    required this.controller,
    required this.currentZoom,
  });

  factory PlateCameraCaptureZoomState.initial() =>
      const PlateCameraCaptureZoomState(
        isReady: false,
        isProcessing: false,
        progress: 0.0,
        message: 'Menyiapkan kamera...',
        lastText: null,
        preview: null,
        controller: null,
        currentZoom: 1.0,
      );

  PlateCameraCaptureZoomState copyWith({
    bool? isReady,
    bool? isProcessing,
    double? progress,
    double? currentZoom,
    Object? message = _sentinel,
    Object? lastText = _sentinel,
    Object? preview = _sentinel,
    Object? controller = _sentinel,
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

    return PlateCameraCaptureZoomState(
      isReady: isReady ?? this.isReady,
      isProcessing: isProcessing ?? this.isProcessing,
      progress: progress ?? this.progress,
      currentZoom: currentZoom ?? this.currentZoom,
      message: nextMessage,
      lastText: nextLastText,
      preview: nextPreview,
      controller: nextController,
    );
  }
}
