import 'dart:io';

import 'package:camerawesome/camerawesome_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  final PhotoController _photoController = PhotoController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => context.read<LensSelectorBloc>().add(const LensSelectorStarted()),
    );
  }

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  Future<void> _capturePhoto(LensSelectorBloc bloc, Sensor? sensor) async {
    if (sensor == null) return;
    bloc.add(const LensSelectorCaptureInitiated());
    try {
      final dynamic capture = await _photoController.takePicture();
      String? path;
      if (capture != null) {
        final dynamic file = capture.file;
        if (file is File) {
          path = file.path;
        } else if (file?.path is String) {
          path = file.path as String;
        } else if (capture is File) {
          path = capture.path;
        } else if (capture?.path is String) {
          path = capture.path as String;
        }
      }

      if (path != null) {
        bloc.add(LensSelectorCaptureCompleted(path));
      } else {
        bloc.add(const LensSelectorCaptureFailed('Gagal menyimpan foto'));
      }
    } catch (e) {
      bloc.add(LensSelectorCaptureFailed(e.toString()));
    }
  }

  Future<String> _buildPath(Sensor sensor) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return p.join(
      dir.path,
      'lens_${sensor.type.name}_$timestamp.jpg',
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
              if (sensor != null)
                Expanded(
                  child: CameraAwesomeBuilder.awesome(
                    key: ValueKey(sensor.type.name),
                    saveConfig: SaveConfig.photo(
                      pathBuilder: (sensor) => _buildPath(sensor),
                    ),
                    sensorConfig: SensorConfig.single(
                      sensor: sensor,
                      flashMode: FlashMode.none,
                      aspectRatio: CameraAspectRatios.ratio_4_3,
                    ),
                    enableAudio: false,
                    photoController: _photoController,
                  ),
                )
              else
                const Expanded(
                  child: Center(
                    child: Text('Tidak ada lensa belakang yang tersedia'),
                  ),
                ),
              const SizedBox(height: 16),
              if (state.sensors.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 12,
                    children: state.sensors
                        .map(
                          (sensor) => ChoiceChip(
                            label: Text(lensZoomLabel(sensor.type)),
                            selected: sensor == state.selectedSensor,
                            onSelected: (_) => bloc.add(
                              LensSelectorSensorSelected(sensor),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: ElevatedButton.icon(
                  onPressed: state.isCapturing
                      ? null
                      : () => _capturePhoto(bloc, state.selectedSensor),
                  icon: state.isCapturing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.camera_alt_rounded),
                  label: Text(state.isCapturing ? 'Mengambil...' : 'Ambil Foto'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
              if (state.lastCapturePath != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Hasil Foto Terakhir',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(state.lastCapturePath!),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (state.message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Text(
                    state.message!,
                    style: const TextStyle(color: Colors.white70),
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
