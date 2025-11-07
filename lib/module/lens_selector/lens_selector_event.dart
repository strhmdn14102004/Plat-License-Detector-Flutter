import 'package:camerawesome/camerawesome_plugin.dart';

abstract class LensSelectorEvent {
  const LensSelectorEvent();
}

class LensSelectorStarted extends LensSelectorEvent {
  const LensSelectorStarted();
}

class LensSelectorSensorSelected extends LensSelectorEvent {
  final Sensor sensor;
  const LensSelectorSensorSelected(this.sensor);
}

class LensSelectorCaptureInitiated extends LensSelectorEvent {
  const LensSelectorCaptureInitiated();
}

class LensSelectorCaptureCompleted extends LensSelectorEvent {
  final String path;
  const LensSelectorCaptureCompleted(this.path);
}

class LensSelectorCaptureFailed extends LensSelectorEvent {
  final String message;
  const LensSelectorCaptureFailed(this.message);
}
