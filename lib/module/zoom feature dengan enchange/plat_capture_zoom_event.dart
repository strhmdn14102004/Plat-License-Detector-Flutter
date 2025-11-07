import 'package:camera/camera.dart';

abstract class PlateCameraCaptureZoomEvent {}

class InitializeCamera extends PlateCameraCaptureZoomEvent {
  final CameraDescription camera;
  InitializeCamera(this.camera);
}

class CapturePhoto extends PlateCameraCaptureZoomEvent {}

class ResetCamera extends PlateCameraCaptureZoomEvent {
  final CameraDescription camera;
  ResetCamera(this.camera);
}

class ZoomCamera extends PlateCameraCaptureZoomEvent {
  final double level;
  ZoomCamera(this.level);
}

class DisposeCamera extends PlateCameraCaptureZoomEvent {}
