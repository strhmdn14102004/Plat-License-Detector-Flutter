import 'package:bloc/bloc.dart';
import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/foundation.dart';

import 'lens_label.dart';
import 'lens_selector_event.dart';
import 'lens_selector_state.dart';

class LensSelectorBloc extends Bloc<LensSelectorEvent, LensSelectorState> {
  LensSelectorBloc() : super(LensSelectorState.initial()) {
    on<LensSelectorStarted>(_onStarted);
    on<LensSelectorSensorSelected>(_onSensorSelected);
    on<LensSelectorCaptureInitiated>(_onCaptureInitiated);
    on<LensSelectorCaptureCompleted>(_onCaptureCompleted);
    on<LensSelectorCaptureFailed>(_onCaptureFailed);
  }

  Future<void> _onStarted(
    LensSelectorStarted event,
    Emitter<LensSelectorState> emit,
  ) async {
    emit(state.copyWith(isLoading: true, message: () => '🔄 Memindai lensa...'));
    try {
      final sensors = await availableSensors();
      final usable = sensors
          .where((sensor) => sensor.position == SensorPosition.back)
          .toList()
        ..sort((a, b) => _lensOrder(a.sensorType).compareTo(_lensOrder(b.sensorType)));

      if (usable.isEmpty) {
        emit(
          state.copyWith(
            isLoading: false,
            sensors: sensors,
            selectedSensor: null,
            error: () => 'Tidak ditemukan lensa belakang pada perangkat ini',
          ),
        );
        return;
      }

      final preferred = usable.firstWhere(
        (sensor) => sensor.sensorType == SensorType.wideAngle,
        orElse: () => usable.first,
      );

      emit(
        state.copyWith(
          isLoading: false,
          sensors: usable,
          selectedSensor: preferred,
          message: () => 'Pilih lensa untuk mengambil foto',
          error: () => null,
        ),
      );
    } catch (e, st) {
      debugPrint('LensSelectorBloc init error: $e\n$st');
      emit(
        state.copyWith(
          isLoading: false,
          error: () => 'Gagal memuat lensa kamera',
          message: () => null,
        ),
      );
    }
  }

  void _onSensorSelected(
    LensSelectorSensorSelected event,
    Emitter<LensSelectorState> emit,
  ) {
    emit(
      state.copyWith(
        selectedSensor: event.sensor,
        message: () => 'Lensa ${lensZoomLabel(event.sensor.type)} dipilih',
        error: () => null,
      ),
    );
  }

  void _onCaptureInitiated(
    LensSelectorCaptureInitiated event,
    Emitter<LensSelectorState> emit,
  ) {
    emit(
      state.copyWith(
        isCapturing: true,
        message: () => '📸 Mengambil foto...',
        error: () => null,
      ),
    );
  }

  void _onCaptureCompleted(
    LensSelectorCaptureCompleted event,
    Emitter<LensSelectorState> emit,
  ) {
    emit(
      state.copyWith(
        isCapturing: false,
        lastCapturePath: event.path,
        message: () => '✅ Foto tersimpan',
        error: () => null,
      ),
    );
  }

  void _onCaptureFailed(
    LensSelectorCaptureFailed event,
    Emitter<LensSelectorState> emit,
  ) {
    emit(
      state.copyWith(
        isCapturing: false,
        error: () => event.message,
        message: () => null,
      ),
    );
  }

  int _lensOrder(SensorType type) {
    switch (type) {
      case SensorType.ultraWideAngle:
        return 0;
      case SensorType.wideAngle:
        return 1;
      case SensorType.telephoto:
        return 2;
      default:
        return 3;
    }
  }

}
