import 'package:camerawesome/camerawesome_plugin.dart' as camerawesome;

extension SensorFactory on camerawesome.SensorTypeDevice {
  camerawesome.Sensor toSensor() {
    final s = camerawesome.Sensor.type(sensorType);
    s.position = camerawesome.SensorPosition.back;
    s.deviceId = uid;
    return s;
  }
}
