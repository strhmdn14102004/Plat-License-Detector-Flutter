import 'package:camera/camera.dart';

abstract class PlateRealtimeEvent {}

class StartRealtimeCamera extends PlateRealtimeEvent {
  final CameraDescription camera;
  StartRealtimeCamera(this.camera);
}

class StopRealtimeCamera extends PlateRealtimeEvent {}

class RealtimeFrameArrived extends PlateRealtimeEvent {
  final CameraImage image;
  final CameraController controller;
  RealtimeFrameArrived(this.image, this.controller);
}

class ChangeRealtimeFlashMode extends PlateRealtimeEvent {
  final FlashMode mode;
  ChangeRealtimeFlashMode(this.mode);
}
