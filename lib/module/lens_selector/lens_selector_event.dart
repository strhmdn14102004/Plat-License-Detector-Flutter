import 'package:camerawesome/camerawesome_plugin.dart' as camerawesome;

typedef Sensor = camerawesome.Sensor;

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
