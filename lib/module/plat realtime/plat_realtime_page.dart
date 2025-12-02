// ignore_for_file: depend_on_referenced_packages, use_build_context_synchronously

import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive/hive.dart';
import 'package:vehicle_identification_number/module/plat realtime/plat_realtime_bloc.dart';
import 'package:vehicle_identification_number/module/plat realtime/plat_realtime_event.dart';
import 'package:vehicle_identification_number/module/plat realtime/plat_realtime_state.dart';

class PlateRealtimePage extends StatefulWidget {
  const PlateRealtimePage({super.key});

  @override
  State<PlateRealtimePage> createState() => _PlateRealtimePageState();
}

class _PlateRealtimePageState extends State<PlateRealtimePage> {
  late PlateRealtimeBloc bloc;
  CameraDescription? _camera;
  bool _sheetVisible = false;

  @override
  void initState() {
    super.initState();
    bloc = context.read<PlateRealtimeBloc>();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    _camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    bloc.add(InitializeRealtimeCamera(_camera!));
  }

  @override
  void dispose() {
    bloc.add(DisposeRealtimeCamera());
    super.dispose();
  }

  Future<void> _showSaveSheet(
    BuildContext context,
    String plate,
    Uint8List? crop,
  ) async {
    if (_sheetVisible) return;
    _sheetVisible = true;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1E23),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              const SizedBox(height: 20),

              Text(
                "Plat Ditemukan!",
                style: TextStyle(
                  fontSize: 22,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              Text(
                plate,
                style: TextStyle(
                  fontSize: 38,
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 12),

              if (crop != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(crop, height: 140),
                ),

              const SizedBox(height: 24),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent,
                  foregroundColor: Colors.black,
                  minimumSize: const Size(double.infinity, 48),
                ),
                onPressed: () async {
                  final box = Hive.box('plates');
                  await box.add({
                    'plate': plate,
                    'time': DateTime.now().toIso8601String(),
                  });

                  Navigator.pop(context);
                },
                icon: const Icon(Icons.check),
                label: const Text("Simpan Data"),
              ),

              const SizedBox(height: 12),

              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Tutup",
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ],
          ),
        );
      },
    );

    _sheetVisible = false;
    bloc.add(UnfreezeRealtimeScanner());
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlateRealtimeBloc, PlateRealtimeState>(
      listener: (context, state) {
        if (!_sheetVisible && state.text != null && state.text!.isNotEmpty) {
          _showSaveSheet(context, state.text!, state.cropped);
        }
      },
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
                  bottom: 140,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Image.memory(state.cropped!, height: 120),
                  ),
                ),

              Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    state.text ?? "Mencari plat…",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 20,
                right: 20,
                child: FloatingActionButton(
                  heroTag: "flashBtn",
                  backgroundColor: Colors.white10,
                  onPressed: () {
                    final next = state.flash == FlashMode.off
                        ? FlashMode.torch
                        : FlashMode.off;
                    bloc.add(ChangeRealtimeFlash(next));
                  },
                  child: Icon(
                    state.flash == FlashMode.off
                        ? Icons.flash_off
                        : Icons.flash_on,
                    color: Colors.white,
                    size: 28,
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
