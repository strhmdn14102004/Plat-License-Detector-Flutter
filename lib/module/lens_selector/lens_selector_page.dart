// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shimmer/shimmer.dart';

import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_bloc.dart';
import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_event.dart';
import 'package:vehicle_identification_number/module/plat%20capture/plat_capture_state.dart';

class LensSelectorPage extends StatefulWidget {
  const LensSelectorPage({super.key});

  @override
  State<LensSelectorPage> createState() => _LensSelectorPageState();
}

class _LensSelectorPageState extends State<LensSelectorPage>
    with SingleTickerProviderStateMixin {
  CameraDescription? _camera;
  late final AnimationController _animCtl;
  CameraController? _configuredController;
  bool _isConfiguringLens = false;

  List<_LensOption> _lensOptions = const [];
  _LensOption? _selectedLens;

  bool _flashSupported = false;
  FlashMode _currentFlashMode = FlashMode.off;

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
    final cameras = await availableCameras();
    _camera = cameras.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final bloc = context.read<PlateCameraCaptureBloc>();
    bloc.add(InitializeCamera(_camera!));
  }

  @override
  void dispose() {
    context.read<PlateCameraCaptureBloc>().add(DisposeCamera());
    _animCtl.dispose();
    super.dispose();
  }

  Future<void> _configureController(CameraController controller) async {
    if (!controller.value.isInitialized || _isConfiguringLens) return;
    if (identical(_configuredController, controller)) return;

    _isConfiguringLens = true;
    _configuredController = controller;

    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();

      final options = <_LensOption>[];
      if (minZoom <= 0.6) {
        options.add(const _LensOption('0.5x', 0.5));
      }

      final standardZoom = _clampZoom(1.0, minZoom, maxZoom);
      options.add(_LensOption('1x', standardZoom));

      if (maxZoom >= 2.0) {
        final teleZoom = maxZoom >= 2.8 ? 3.0 : maxZoom;
        final label = teleZoom >= 2.8 ? '3x' : '${teleZoom.toStringAsFixed(1)}x';
        options.add(_LensOption(label, teleZoom));
      }

      _lensOptions = options;

      final match = _matchExistingSelection(options);
      final targetZoom = _clampZoom(match.zoom, minZoom, maxZoom);

      try {
        await controller.setZoomLevel(targetZoom);
      } catch (_) {}

      final actualZoom = controller.value.zoomLevel;
      _selectedLens = _matchSelectionByZoom(options, actualZoom) ?? match;

      _flashSupported = await _ensureFlash(controller);
    } finally {
      if (mounted) {
        setState(() {});
      }
      _isConfiguringLens = false;
    }
  }

  Future<bool> _ensureFlash(CameraController controller) async {
    _currentFlashMode = FlashMode.off;
    try {
      await controller.setFlashMode(_currentFlashMode);
      return true;
    } on CameraException {
      return false;
    }
  }

  _LensOption _matchExistingSelection(List<_LensOption> options) {
    if (_selectedLens != null) {
      final existing = _matchSelectionByZoom(options, _selectedLens!.zoom);
      if (existing != null) {
        return existing;
      }
    }

    final standard = options.firstWhere(
      (opt) => opt.label == '1x',
      orElse: () => options.first,
    );
    return standard;
  }

  _LensOption? _matchSelectionByZoom(
    List<_LensOption> options,
    double zoom,
  ) {
    const epsilon = 0.05;
    for (final option in options) {
      if ((option.zoom - zoom).abs() <= epsilon) {
        return option;
      }
    }
    return null;
  }

  double _clampZoom(double value, double minZoom, double maxZoom) {
    if (value < minZoom) return minZoom;
    if (value > maxZoom) return maxZoom;
    return value;
  }

  Future<void> _selectLens(_LensOption option) async {
    final controller = context.read<PlateCameraCaptureBloc>().state.controller;
    if (controller == null) return;
    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final zoom = _clampZoom(option.zoom, minZoom, maxZoom);
      await controller.setZoomLevel(zoom);
      if (!mounted) return;
      setState(() {
        _selectedLens = option;
      });
    } catch (_) {}
  }

  Future<void> _toggleFlash() async {
    if (!_flashSupported) return;
    final controller = context.read<PlateCameraCaptureBloc>().state.controller;
    if (controller == null) return;

    FlashMode nextMode;
    switch (_currentFlashMode) {
      case FlashMode.off:
        nextMode = FlashMode.auto;
        break;
      case FlashMode.auto:
        nextMode = FlashMode.torch;
        break;
      default:
        nextMode = FlashMode.off;
        break;
    }

    try {
      await controller.setFlashMode(nextMode);
      if (!mounted) return;
      setState(() {
        _currentFlashMode = nextMode;
      });
    } on CameraException {
      if (!mounted) return;
      setState(() {
        _currentFlashMode = FlashMode.off;
        _flashSupported = false;
      });
    }
  }

  IconData _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.off:
        return Icons.flash_off_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on_rounded;
    }
  }

  String _lensSummary() {
    if (_lensOptions.isEmpty) return '-';
    return _lensOptions.map((opt) => opt.label).join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlateCameraCaptureBloc, PlateCameraCaptureState>(
      listener: (context, state) async {
        final controller = state.controller;
        if (controller != null && controller.value.isInitialized) {
          await _configureController(controller);
        }

        if (controller == null) {
          _configuredController = null;
          _lensOptions = const [];
          _selectedLens = null;
          if (mounted) setState(() {});
        }

        if (!state.isProcessing &&
            state.lastText != null &&
            state.preview != null) {
          await _showResult(context, state.lastText!);
          if (_camera != null) {
            context
                .read<PlateCameraCaptureBloc>()
                .add(ResetCamera(_camera!));
          }
        }
      },
      builder: (context, state) {
        final controller = state.controller;
        final preview = state.preview;

        return Scaffold(
          backgroundColor: const Color(0xFF0B1220),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: const Text('Multi-Lens Capture'),
            centerTitle: true,
            actions: [
              if (_flashSupported)
                IconButton(
                  icon: Icon(_flashIcon(_currentFlashMode)),
                  tooltip: 'Ubah mode flash',
                  onPressed: state.isProcessing ? null : _toggleFlash,
                ),
            ],
          ),
          body: SafeArea(
            child: Stack(
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
                                builder: (_, __) => BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 10 * _animCtl.value,
                                    sigmaY: 10 * _animCtl.value,
                                  ),
                                  child: Shimmer.fromColors(
                                    baseColor: Colors.tealAccent.withOpacity(0.25),
                                    highlightColor:
                                        Colors.white.withOpacity(0.1),
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
                    child:
                        CircularProgressIndicator(color: Colors.tealAccent),
                  ),

                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lensa tersedia',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _lensSummary(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    bottom: 170,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        state.message!,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),

                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_lensOptions.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Wrap(
                            spacing: 12,
                            children: _lensOptions
                                .map(
                                  (option) => ChoiceChip(
                                    label: Text(option.label),
                                    selected: _selectedLens == option,
                                    onSelected: state.isProcessing
                                        ? null
                                        : (_) => _selectLens(option),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      const SizedBox(height: 14),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: Text(
                          state.isProcessing
                              ? 'Memproses...'
                              : 'Ambil Foto',
                        ),
                        onPressed: state.isReady && !state.isProcessing
                            ? () => context
                                .read<PlateCameraCaptureBloc>()
                                .add(CapturePhoto())
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
                    ],
                  ),
                ),
              ],
            ),
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

class _LensOption {
  final String label;
  final double zoom;

  const _LensOption(this.label, this.zoom);

  @override
  bool operator ==(Object other) {
    return other is _LensOption &&
        other.label == label &&
        (other.zoom - zoom).abs() < 0.01;
  }

  @override
  int get hashCode => Object.hash(label, zoom.toStringAsFixed(2));
}
