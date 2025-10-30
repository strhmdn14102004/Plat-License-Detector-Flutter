import 'package:camera/camera.dart';

abstract class PlateEvent {}

class StartCamera extends PlateEvent {
  final CameraDescription camera;
  StartCamera(this.camera);
}

class StopCamera extends PlateEvent {}

class ProcessCameraImage extends PlateEvent {
  final CameraImage cameraImage;
  final CameraController controller;
  ProcessCameraImage(this.cameraImage, this.controller);
}

class ManualScanTrigger extends PlateEvent {}
