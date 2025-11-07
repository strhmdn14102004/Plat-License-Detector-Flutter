import 'package:camerawesome/camerawesome_plugin.dart';

class LensSelectorState {
  final bool isLoading;
  final bool isCapturing;
  final List<Sensor> sensors;
  final Sensor? selectedSensor;
  final String? lastCapturePath;
  final String? message;
  final String? error;

  const LensSelectorState({
    required this.isLoading,
    required this.isCapturing,
    required this.sensors,
    required this.selectedSensor,
    required this.lastCapturePath,
    required this.message,
    required this.error,
  });

  factory LensSelectorState.initial() {
    return const LensSelectorState(
      isLoading: false,
      isCapturing: false,
      sensors: <Sensor>[],
      selectedSensor: null,
      lastCapturePath: null,
      message: null,
      error: null,
    );
  }

  LensSelectorState copyWith({
    bool? isLoading,
    bool? isCapturing,
    List<Sensor>? sensors,
    Sensor? selectedSensor,
    String? lastCapturePath,
    String? Function()? message,
    String? Function()? error,
  }) {
    return LensSelectorState(
      isLoading: isLoading ?? this.isLoading,
      isCapturing: isCapturing ?? this.isCapturing,
      sensors: sensors ?? this.sensors,
      selectedSensor: selectedSensor ?? this.selectedSensor,
      lastCapturePath: lastCapturePath ?? this.lastCapturePath,
      message: message != null ? message() : this.message,
      error: error != null ? error() : this.error,
    );
  }
}
