import 'package:camerawesome/camerawesome_plugin.dart' as camerawesome;

typedef SensorType = camerawesome.SensorType;

String lensZoomLabel(SensorType type) {
  switch (type) {
    case SensorType.ultraWideAngle:
      return '0.5x';
    case SensorType.wideAngle:
      return '1x';
    case SensorType.telephoto:
      return '3x';
    default:
      return type.name;
  }
}
