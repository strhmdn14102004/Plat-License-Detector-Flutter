import 'package:camera/camera.dart';

abstract class PlateCameraCaptureEvent {}

class InitializeCamera extends PlateCameraCaptureEvent {
  final CameraDescription camera;
  InitializeCamera(this.camera);
}

class CapturePhoto extends PlateCameraCaptureEvent {}

class ResetCamera extends PlateCameraCaptureEvent {
  final CameraDescription camera;
  ResetCamera(this.camera);
}

class UpdateEnhancement extends PlateCameraCaptureEvent {
  final double brightness;
  final double contrast;

  UpdateEnhancement({required this.brightness, required this.contrast});
}

class DisposeCamera extends PlateCameraCaptureEvent {}
