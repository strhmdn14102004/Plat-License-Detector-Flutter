import 'dart:typed_data';

import 'package:camera/camera.dart';

abstract class PlateCameraCaptureEvent {}

class InitializeCamera extends PlateCameraCaptureEvent {
  final CameraDescription camera;
  InitializeCamera(this.camera);
}

class CapturePhoto extends PlateCameraCaptureEvent {}

class ProcessExternalPhoto extends PlateCameraCaptureEvent {
  final Uint8List bytes;

  ProcessExternalPhoto(this.bytes);
}

class ResetCamera extends PlateCameraCaptureEvent {
  final CameraDescription camera;
  ResetCamera(this.camera);
}

class DisposeCamera extends PlateCameraCaptureEvent {}
