import 'package:camera/camera.dart';

abstract class PlateCaptureEvent {}

class StartCaptureCamera extends PlateCaptureEvent {
  final CameraDescription camera;
  StartCaptureCamera(this.camera);
}

class StopCaptureCamera extends PlateCaptureEvent {}

class CaptureAndProcessFrame extends PlateCaptureEvent {
  final CameraDescription camera;
  CaptureAndProcessFrame(this.camera);
}
