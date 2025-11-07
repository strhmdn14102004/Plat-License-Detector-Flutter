// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shimmer/shimmer.dart';

import 'plat_capture_zoom_bloc.dart';
import 'plat_capture_zoom_event.dart';
import 'plat_capture_zoom_state.dart';

class PlateCameraCaptureZoomPage extends StatefulWidget {
  const PlateCameraCaptureZoomPage({super.key});

  @override
  State<PlateCameraCaptureZoomPage> createState() =>
      _PlateCameraCaptureZoomPageState();
}

class _PlateCameraCaptureZoomPageState extends State<PlateCameraCaptureZoomPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  CameraDescription? _camera;
  late final AnimationController _animCtl;

  double _baseZoom = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

    context.read<PlateCameraCaptureZoomBloc>().add(InitializeCamera(_camera!));

    Future.delayed(const Duration(milliseconds: 800), () async {
      final bloc = context.read<PlateCameraCaptureZoomBloc>();
      final controller = bloc.state.controller;
      if (controller != null && controller.value.isInitialized) {
        final min = await controller.getMinZoomLevel();
        final max = await controller.getMaxZoomLevel();
        setState(() {
          _minZoom = min;
          _maxZoom = max;
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context.read<PlateCameraCaptureZoomBloc>().add(DisposeCamera());
    _animCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<
      PlateCameraCaptureZoomBloc,
      PlateCameraCaptureZoomState
    >(
      listener: (context, state) async {
        if (!state.isProcessing &&
            state.lastText != null &&
            state.preview != null) {
          await _showResult(context, state.lastText!);
          context.read<PlateCameraCaptureZoomBloc>().add(ResetCamera(_camera!));
        }
      },
      builder: (context, state) {
        final controller = state.controller;
        final preview = state.preview;
        final currentZoom = state.currentZoom;

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
                GestureDetector(
                  onScaleStart: (details) => _baseZoom = currentZoom,
                  onScaleUpdate: (details) {
                    if (details.scale != 1.0) {
                      final newZoom = (_baseZoom * details.scale).clamp(
                        _minZoom,
                        _maxZoom,
                      );
                      context.read<PlateCameraCaptureZoomBloc>().add(
                        ZoomCamera(newZoom),
                      );
                    }
                  },
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CameraPreview(controller),

                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "🔍 x${currentZoom.toStringAsFixed(1)}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Colors.tealAccent),
                ),

              if (state.isProcessing)
                Positioned(
                  bottom: 120,
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
                  bottom: 80,
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

              if (controller != null && controller.value.isInitialized)
                Positioned(
                  bottom: 160,
                  left: 40,
                  right: 40,
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          activeTrackColor: Colors.tealAccent,
                          inactiveTrackColor: Colors.white24,
                          thumbColor: Colors.tealAccent,
                          overlayColor: Colors.tealAccent.withOpacity(0.2),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          min: _minZoom,
                          max: _maxZoom > _minZoom ? _maxZoom : _minZoom + 1,
                          divisions: 20,
                          value: currentZoom.clamp(_minZoom, _maxZoom),
                          label: "x${currentZoom.toStringAsFixed(1)}",
                          onChanged: (v) => context
                              .read<PlateCameraCaptureZoomBloc>()
                              .add(ZoomCamera(v)),
                        ),
                      ),
                      const Text(
                        "Geser atau cubit layar untuk zoom",
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
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
                        ? () => context.read<PlateCameraCaptureZoomBloc>().add(
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
