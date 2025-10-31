// ignore_for_file: curly_braces_in_flow_control_structures, deprecated_member_use, use_build_context_synchronously

import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:face_recognition/module/plat/plat_bloc.dart';
import 'package:face_recognition/module/plat/plat_event.dart';
import 'package:face_recognition/module/plat/plat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

class PlateScanPage extends StatefulWidget {
  const PlateScanPage({super.key});
  @override
  State<PlateScanPage> createState() => _PlateScanPageState();
}

class _PlateScanPageState extends State<PlateScanPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraDescription? _selectedCamera;
  bool _initialized = false;
  bool _scanning = false;
  bool _wasScanningBeforePause = false;

  late PlateBloc _bloc;
  bool _blocBound = false;

  final List<String> _savedPlates = [];

  static const bool kShowDebugBox = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_blocBound) {
      _bloc = context.read<PlateBloc>();
      _blocBound = true;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCameras().then((_) {
      if (_selectedCamera != null) {
        setState(() => _initialized = true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _wasScanningBeforePause = _scanning;
      if (_scanning) _stopScan();
    } else if (state == AppLifecycleState.resumed) {
      if (_wasScanningBeforePause && _selectedCamera != null) {
        _startScan();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloc.add(StopCamera());
    super.dispose();
  }

  Future<void> _loadCameras() async {
    try {
      final cameras = await availableCameras();
      _selectedCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
    } catch (e) {
      debugPrint("Camera error: $e");
    }
  }

  Future<void> _startScan() async {
    if (_selectedCamera == null || _scanning) return;
    await Future.delayed(const Duration(milliseconds: 120));
    _bloc.add(StartCamera(_selectedCamera!));
    if (mounted) setState(() => _scanning = true);
  }

  void _stopScan() {
    if (!_scanning) return;
    _bloc.add(StopCamera());
    if (mounted) setState(() => _scanning = false);
  }

  void _toggleScan() => _scanning ? _stopScan() : _startScan();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (!didPop) _stopScan();
      },
      child: BlocConsumer<PlateBloc, PlateState>(
        listener: (context, state) {
          if (state.lastText != null) {
            final text = state.lastText!.trim();
            final lines = text.split('\n').map((e) => e.trim()).toList();

            final plateRegex = RegExp(r'^[A-Z]{1,2}\s?\d{1,4}\s?[A-Z]{0,3}$');
            final timeRegex = RegExp(r'^\d{2}[:.,]?\d{2}$');

            String? plate;
            String? time;
            for (final l in lines) {
              if (plate == null && plateRegex.hasMatch(l)) {
                plate = l;
              } else if (time == null && timeRegex.hasMatch(l))
                time = l;
            }

            if (plate != null && time != null) {
              final cleanText = '$plate\n$time';
              if (!_savedPlates.contains(cleanText)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _showSaveBottomSheet(context, cleanText);
                });
              }
            }
          }
        },
        builder: (context, state) {
          final controller = state.controller;
          return Scaffold(
            backgroundColor: const Color(0xFF0B1220),
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              title: const Text("License Plate Scanner"),
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
              leading: IconButton(
                icon: const Icon(Icons.turn_left_rounded),
                onPressed: () {
                  _stopScan();
                  Navigator.of(context).maybePop();
                },
              ),
            ),
            body: !_initialized
                ? const Center(child: CircularProgressIndicator())
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      _GradientBackground(),

                      if (_scanning &&
                          state.isCameraReady &&
                          controller != null &&
                          controller.value.isInitialized)
                        _CameraLayer(
                          controller: controller,
                          state: state,
                          showBox: kShowDebugBox,
                        )
                      else
                        const _IdleLayer(),

                      const _FocusOverlay(),

                      Positioned(
                        top: kToolbarHeight + 40,
                        left: 20,
                        right: 20,
                        child: _HudStatus(
                          scanning: _scanning,
                          isReady: state.isCameraReady,
                          message: state.message,
                        ),
                      ),

                      const Positioned(
                        bottom: 120,
                        left: 16,
                        right: 16,
                        child: _GpuHint(),
                      ),

                      Positioned(
                        bottom: 40,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: _toggleButton(
                            scanning: _scanning,
                            onTap: _toggleScan,
                          ),
                        ),
                      ),

                      if (_savedPlates.isNotEmpty)
                        Positioned(
                          bottom: 190,
                          left: 16,
                          right: 16,
                          child: _LastResultToast(text: _savedPlates.last),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  static Widget _toggleButton({
    required bool scanning,
    required VoidCallback onTap,
  }) {
    final color = scanning ? Colors.redAccent : Colors.greenAccent;
    final icon = scanning ? Icons.stop_rounded : Icons.play_arrow_rounded;
    final label = scanning ? "Stop" : "Start";

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.16),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: color.withOpacity(0.9), width: 1.8),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.45),
              blurRadius: 18,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSaveBottomSheet(BuildContext context, String plateText) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black.withOpacity(0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
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
              const Text(
                'Plat Terbaca',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                plateText,
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        'Simpan',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () async {
                        final box = Hive.box('plates');
                        final List<String> existing = List<String>.from(
                          box.get('data', defaultValue: []),
                        );
                        if (!existing.contains(plateText)) {
                          existing.add(plateText);
                          await box.put('data', existing);

                          _savedPlates.add(plateText);
                          setState(() {});
                        }
                        Navigator.pop(ctx);
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
                        side: const BorderSide(color: Colors.white30),
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

class _GradientBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

class _CameraLayer extends StatelessWidget {
  final CameraController controller;
  final PlateState state;
  final bool showBox;
  const _CameraLayer({
    required this.controller,
    required this.state,
    required this.showBox,
  });

  @override
  Widget build(BuildContext context) {
    final previewSize = controller.value.previewSize!;
    return Stack(
      children: [
        Center(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: previewSize.height,
              height: previewSize.width,
              child: CameraPreview(controller),
            ),
          ),
        ),

        if (showBox && state.lastBox != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: state.lastBox!.left,
            top: state.lastBox!.top,
            width: state.lastBox!.width,
            height: state.lastBox!.height,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.greenAccent.withOpacity(0.95),
                    width: 3,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withOpacity(0.35),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _IdleLayer extends StatelessWidget {
  const _IdleLayer();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.camera_alt_outlined, color: Colors.white60, size: 50),
          SizedBox(height: 6),
          Text(
            'Tekan start untuk memulai scanner',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _FocusOverlay extends StatelessWidget {
  const _FocusOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: Container(
          width: MediaQuery.sizeOf(context).width * 0.78,
          height: 120,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(0.28),
              width: 1.6,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.tealAccent.withOpacity(0.18),
                blurRadius: 18,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HudStatus extends StatelessWidget {
  final bool scanning;
  final bool isReady;
  final String? message;
  const _HudStatus({
    required this.scanning,
    required this.isReady,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    final text = !scanning
        ? "Idle — tekan Start"
        : (isReady ? (message ?? "Mendeteksi…") : "Menyiapkan kamera…");
    final color = scanning ? Colors.lightGreenAccent : Colors.white70;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.08),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                scanning
                    ? Icons.speed_rounded
                    : Icons.pause_circle_outline_rounded,
                color: color,
                size: 18,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GpuHint extends StatelessWidget {
  const _GpuHint();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.07),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.memory_rounded, color: Colors.tealAccent, size: 25),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Gunakan perangkat dengan GPU/NNAPI/Metal agar deteksi lebih cepat dan stabil.",
                    style: TextStyle(color: Colors.white, fontSize: 12.5),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LastResultToast extends StatelessWidget {
  final String text;
  const _LastResultToast({required this.text});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.45),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withOpacity(0.25),
                blurRadius: 14,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Hasil Scan Terakhir",
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 1.05,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
