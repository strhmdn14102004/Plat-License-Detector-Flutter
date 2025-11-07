// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shimmer/shimmer.dart';

import 'plat_capture_bloc.dart';
import 'plat_capture_event.dart';
import 'plat_capture_state.dart';

class PlateCameraCapturePage extends StatefulWidget {
  const PlateCameraCapturePage({super.key});

  @override
  State<PlateCameraCapturePage> createState() => _PlateCameraCapturePageState();
}

class _PlateCameraCapturePageState extends State<PlateCameraCapturePage>
    with SingleTickerProviderStateMixin {
  CameraDescription? _camera;
  late final AnimationController _animCtl;

  @override
  void initState() {
    super.initState();
    _animCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    _camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    context.read<PlateCameraCaptureBloc>().add(InitializeCamera(_camera!));
  }

  @override
  void dispose() {
    context.read<PlateCameraCaptureBloc>().add(DisposeCamera());
    _animCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlateCameraCaptureBloc, PlateCameraCaptureState>(
      listener: (context, state) async {
        if (!state.isProcessing &&
            state.lastText != null &&
            state.preview != null) {
          await _showResult(context, state.lastText!);
          context.read<PlateCameraCaptureBloc>().add(ResetCamera(_camera!));
        }
      },
      builder: (context, state) {
        final controller = state.controller;
        final preview = state.preview;

        return Scaffold(
          backgroundColor: const Color(0xFF0B1220),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text("Mode Kamera Scanner"),
          ),
          body: Stack(
            children: [
              if (preview != null)
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 400),
                  child: Center(
                    key: ValueKey(preview),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            preview,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                          if (state.isProcessing)
                            AnimatedBuilder(
                              animation: _animCtl..forward(),
                              builder: (_, _) => BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 10 * _animCtl.value,
                                  sigmaY: 10 * _animCtl.value,
                                ),
                                child: Shimmer.fromColors(
                                  baseColor: Colors.tealAccent.withOpacity(
                                    0.25,
                                  ),
                                  highlightColor: Colors.white.withOpacity(0.1),
                                  child: Container(
                                    color: Colors.black.withOpacity(0.25),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (controller != null && controller.value.isInitialized)
                CameraPreview(controller)
              else
                const Center(
                  child: CircularProgressIndicator(color: Colors.tealAccent),
                ),

              if (state.isProcessing)
                Positioned(
                  bottom: 110,
                  left: 50,
                  right: 50,
                  child: LinearProgressIndicator(
                    value: state.progress,
                    color: Colors.tealAccent,
                    backgroundColor: Colors.white10,
                  ),
                ),

              if (state.message != null)
                Positioned(
                  bottom: 70,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Text(
                      state.message!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),

              Positioned(
                bottom: 25,
                left: 0,
                right: 0,
                child: Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.camera_alt),
                    label: Text(
                      state.isProcessing ? "Memproses..." : "Ambil Foto",
                    ),
                    onPressed: state.isReady && !state.isProcessing
                        ? () => context.read<PlateCameraCaptureBloc>().add(
                            CapturePhoto(),
                          )
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.tealAccent.withOpacity(0.3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 30,
                        vertical: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
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

  Future<void> _showResult(BuildContext context, String text) async {
    final outerContext = context;
    final normalized = text.trim();
    final canSave =
        normalized.isNotEmpty &&
        normalized.toLowerCase() != 'tidak terbaca' &&
        normalized.toLowerCase() != 'error';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final box = Hive.box('plates');
        final existing = List<String>.from(box.get('data', defaultValue: []));
        final alreadySaved = existing.contains(normalized);

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Wrap(
            children: [
              Center(
                child: Container(
                  height: 4,
                  width: 40,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Center(
                child: Text(
                  'Plat Terbaca',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  normalized,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: Text(
                        alreadySaved ? 'Sudah Tersimpan' : 'Simpan',
                        style: const TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSave && !alreadySaved
                            ? Colors.green
                            : Colors.white12,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: (!canSave || alreadySaved)
                          ? null
                          : () async {
                              existing.add(normalized);
                              await box.put('data', existing);
                              if (mounted) {
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(outerContext).showSnackBar(
                                  SnackBar(
                                    content: Text('Plat $normalized disimpan'),
                                  ),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      label: const Text(
                        'Tutup',
                        style: TextStyle(color: Colors.white70),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
