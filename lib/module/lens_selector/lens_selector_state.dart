import 'package:camerawesome/camerawesome_plugin.dart' as camerawesome;

typedef Sensor = camerawesome.Sensor;

class LensSelectorState {
  final bool isLoading;
  final List<Sensor> sensors;
  final Sensor? selectedSensor;
  final String? message;
  final String? error;

  const LensSelectorState({
    required this.isLoading,
    required this.sensors,
    required this.selectedSensor,
    required this.message,
    required this.error,
  });

  factory LensSelectorState.initial() {
    return const LensSelectorState(
      isLoading: false,
      sensors: <Sensor>[],
      selectedSensor: null,
      message: null,
      error: null,
    );
  }

  LensSelectorState copyWith({
    bool? isLoading,
    List<Sensor>? sensors,
    Sensor? Function()? selectedSensor,
    String? Function()? message,
    String? Function()? error,
  }) {
    return LensSelectorState(
      isLoading: isLoading ?? this.isLoading,
      sensors: sensors ?? this.sensors,
      selectedSensor:
          selectedSensor != null ? selectedSensor() : this.selectedSensor,
      message: message != null ? message() : this.message,
      error: error != null ? error() : this.error,
    );
  }
}
