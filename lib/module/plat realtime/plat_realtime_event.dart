import 'package:camera/camera.dart';

abstract class PlateRealtimeEvent {}

class InitializeRealtimeCamera extends PlateRealtimeEvent {
  final CameraDescription camera;
  InitializeRealtimeCamera(this.camera);
}

class DisposeRealtimeCamera extends PlateRealtimeEvent {}

class UnfreezeRealtimeScanner extends PlateRealtimeEvent {}

class ChangeRealtimeFlash extends PlateRealtimeEvent {
  final FlashMode mode;
  ChangeRealtimeFlash(this.mode);
}
