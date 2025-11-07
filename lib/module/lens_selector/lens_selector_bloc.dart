// ignore_for_file: depend_on_referenced_packages

import 'package:bloc/bloc.dart';
import 'package:camerawesome/camerawesome_plugin.dart' as camerawesome;
import 'package:flutter/foundation.dart';

import 'lens_label.dart';
import 'lens_selector_event.dart';
import 'lens_selector_state.dart';

typedef Sensor = camerawesome.SensorTypeDevice;
typedef SensorType = camerawesome.SensorType;

class LensSelectorBloc extends Bloc<LensSelectorEvent, LensSelectorState> {
  LensSelectorBloc() : super(LensSelectorState.initial()) {
    on<LensSelectorStarted>(_onStarted);
    on<LensSelectorSensorSelected>(_onSensorSelected);
  }

  Future<void> _onStarted(
    LensSelectorStarted event,
    Emitter<LensSelectorState> emit,
  ) async {
    emit(
      state.copyWith(isLoading: true, message: () => '🔄 Memindai lensa...'),
    );
    try {
      final sensorData = await camerawesome.CamerawesomePlugin.getSensors();
      final usable = <camerawesome.SensorTypeDevice>[];

      if (sensorData.wideAngle != null) usable.add(sensorData.wideAngle!);
      if (sensorData.ultraWideAngle != null) {
        usable.add(sensorData.ultraWideAngle!);
      }
      if (sensorData.telephoto != null) usable.add(sensorData.telephoto!);

      usable.sort(
        (a, b) => _lensOrder(a.sensorType).compareTo(_lensOrder(b.sensorType)),
      );

      if (usable.isEmpty) {
        emit(
          state.copyWith(
            isLoading: false,
            sensors: const <Sensor>[],
            selectedSensor: () => null,
            error: () => 'Tidak ditemukan lensa belakang pada perangkat ini',
            message: () => null,
          ),
        );
        return;
      }

      final preferred = usable.firstWhere(
        (s) => s.sensorType == camerawesome.SensorType.wideAngle,
        orElse: () => usable.first,
      );

      emit(
        state.copyWith(
          isLoading: false,
          sensors: usable,
          selectedSensor: () => preferred,
          message: () => 'Pilih lensa kamera (0.5x / 1x / 3x)',
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
    if (state.selectedSensor == event.sensor) {
      emit(
        state.copyWith(
          message: () =>
              'Lensa ${lensZoomLabel(event.sensor.sensorType)} sudah aktif',
          error: () => null,
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        selectedSensor: () => event.sensor,
        message: () =>
            'Lensa ${lensZoomLabel(event.sensor.sensorType)} aktif. Gunakan tombol rana untuk memotret',
        error: () => null,
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
