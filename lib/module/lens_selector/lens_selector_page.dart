import 'package:camerawesome/camerawesome_plugin.dart' as camerawesome;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'lens_label.dart';
import 'lens_selector_bloc.dart';
import 'lens_selector_event.dart';
import 'lens_selector_state.dart';

class LensSelectorPage extends StatefulWidget {
  const LensSelectorPage({super.key});

  @override
  State<LensSelectorPage> createState() => _LensSelectorPageState();
}

class _LensSelectorPageState extends State<LensSelectorPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => context.read<LensSelectorBloc>().add(const LensSelectorStarted()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pilih Lensa Kamera'),
      ),
      body: BlocConsumer<LensSelectorBloc, LensSelectorState>(
        listener: (context, state) {
          final messenger = ScaffoldMessenger.of(context);
          if (state.error != null) {
            messenger.hideCurrentSnackBar();
            messenger.showSnackBar(
              SnackBar(
                content: Text(state.error!),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          final bloc = context.read<LensSelectorBloc>();
          final sensor = state.selectedSensor;

          return Column(
            children: [
              Expanded(
                child: sensor != null
                    ? KeyedSubtree(
                        key: ValueKey(sensor.sensorType.name),
                        child: camerawesome.CameraAwesomeBuilder.awesome(
                          sensorConfig: camerawesome.SensorConfig.single(
                            sensor: sensor,
                            flashMode: camerawesome.FlashMode.none,
                            aspectRatio: camerawesome.CameraAspectRatios.ratio_4_3,
                          ),
                          saveConfig: camerawesome.SaveConfig.photo(),
                        ),
                      )
                    : const Center(
                        child: Text('Tidak ada lensa belakang yang tersedia'),
                      ),
              ),
              if (state.sensors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: state.sensors
                        .map(
                          (sensor) => ChoiceChip(
                            label: Text(lensZoomLabel(sensor.sensorType)),
                            selected: sensor == state.selectedSensor,
                            onSelected: (_) => bloc.add(
                              LensSelectorSensorSelected(sensor),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              if (state.message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Text(
                    state.message!,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
