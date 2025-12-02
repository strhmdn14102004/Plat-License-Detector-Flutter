// ignore_for_file: use_build_context_synchronously

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vehicle_identification_number/module/plat%20realtime/plat_realtime_bloc.dart';
import 'package:vehicle_identification_number/module/plat%20realtime/plat_realtime_event.dart';
import 'package:vehicle_identification_number/module/plat%20realtime/plat_realtime_state.dart';

class PlateRealtimePage extends StatefulWidget {
  const PlateRealtimePage({super.key});

  @override
  State<PlateRealtimePage> createState() => _PlateRealtimePageState();
}

class _PlateRealtimePageState extends State<PlateRealtimePage> {
  CameraDescription? _camera;

  @override
  void initState() {
    super.initState();
    _initCam();
  }

  Future<void> _initCam() async {
    final cams = await availableCameras();
    _camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    context.read<PlateRealtimeBloc>().add(InitializeRealtimeCamera(_camera!));
  }

  @override
  void dispose() {
    context.read<PlateRealtimeBloc>().add(DisposeRealtimeCamera());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<PlateRealtimeBloc, PlateRealtimeState>(
      builder: (context, state) {
        final cam = state.controller;

        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            title: const Text("Realtime Plate Scanner"),
            backgroundColor: Colors.transparent,
          ),
          body: Stack(
            children: [
              if (cam != null && cam.value.isInitialized)
                Positioned.fill(child: CameraPreview(cam)),

              if (state.cropped != null)
                Positioned(
                  bottom: 120,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.memory(state.cropped!, height: 90),
                  ),
                ),

              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    state.text ?? "Cari plat...",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
