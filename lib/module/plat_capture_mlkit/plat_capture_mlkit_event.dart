import 'package:camera/camera.dart';

abstract class PlateMlkitCaptureEvent {}

class InitializeMlkitCamera extends PlateMlkitCaptureEvent {
  final CameraDescription camera;
  InitializeMlkitCamera(this.camera);
}

class CaptureMlkitPhoto extends PlateMlkitCaptureEvent {}

class ResetMlkitCamera extends PlateMlkitCaptureEvent {
  final CameraDescription camera;
  ResetMlkitCamera(this.camera);
}

class DisposeMlkitCamera extends PlateMlkitCaptureEvent {}

class ChangeMlkitFlashMode extends PlateMlkitCaptureEvent {
  final FlashMode mode;
  ChangeMlkitFlashMode(this.mode);
}
