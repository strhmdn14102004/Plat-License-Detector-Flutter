// ignore_for_file: unnecessary_const

import 'dart:ui';

import 'package:camera/camera.dart';

class PlateRealtimeState {
  static const Object _sentinel = const Object();
  final bool isCameraReady;
  final CameraController? controller;
  final bool isProcessing;
  final Rect? lastBox;
  final String? lastText;
  final List<String> detected;
  final String? message;

  const PlateRealtimeState({
    required this.isCameraReady,
    required this.controller,
    required this.isProcessing,
    required this.lastBox,
    required this.lastText,
    required this.detected,
    required this.message,
  });

  factory PlateRealtimeState.initial() => const PlateRealtimeState(
    isCameraReady: false,
    controller: null,
    isProcessing: false,
    lastBox: null,
    lastText: null,
    detected: [],
    message: null,
  );

  PlateRealtimeState copyWith({
    bool? isCameraReady,
    Object? controller = _sentinel,
    bool? isProcessing,
    Object? lastBox = _sentinel,
    Object? lastText = _sentinel,
    List<String>? detected,
    Object? message = _sentinel,
  }) {
    final CameraController? nextController = identical(controller, _sentinel)
        ? this.controller
        : controller as CameraController?;
    final Rect? nextBox = identical(lastBox, _sentinel)
        ? this.lastBox
        : lastBox as Rect?;
    final String? nextText = identical(lastText, _sentinel)
        ? this.lastText
        : lastText as String?;
    final String? nextMessage = identical(message, _sentinel)
        ? this.message
        : message as String?;

    return PlateRealtimeState(
      isCameraReady: isCameraReady ?? this.isCameraReady,
      controller: nextController,
      isProcessing: isProcessing ?? this.isProcessing,
      lastBox: nextBox,
      lastText: nextText,
      detected: detected ?? this.detected,
      message: nextMessage,
    );
  }
}
