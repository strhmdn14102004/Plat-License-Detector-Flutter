// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:face_recognition/module/plat%20capture/plat_capture_bloc.dart';
import 'package:face_recognition/module/plat%20capture/plat_capture_event.dart';
import 'package:face_recognition/module/plat%20capture/plat_capture_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

class PlateScanCapturePage extends StatefulWidget {
  const PlateScanCapturePage({super.key});
  @override
  State<PlateScanCapturePage> createState() => _PlateScanCapturePageState();
}

class _PlateScanCapturePageState extends State<PlateScanCapturePage>
    with WidgetsBindingObserver {
  CameraDescription? _camera;
  late PlateCaptureBloc _bloc;
  bool _flash = false;
  bool _bottomSheetVisible = false;
  final List<String> _savedPlates = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = context.read<PlateCaptureBloc>();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();
    _camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    _bloc.add(StartCaptureCamera(_camera!));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bloc.add(StopCaptureCamera());
    super.dispose();
  }

  Future<void> _capture() async {
    setState(() => _flash = true);
    await Future.delayed(const Duration(milliseconds: 120));
    setState(() => _flash = false);
    _bloc.add(CaptureAndProcessFrame(_camera!));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (!didPop) _bloc.add(StopCaptureCamera());
      },
      child: BlocConsumer<PlateCaptureBloc, PlateCaptureState>(
        listener: (context, state) {
          if (state.lastText != null &&
              !_bottomSheetVisible &&
              !state.isProcessing) {
            _bottomSheetVisible = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              await _showSaveBottomSheet(context, state.lastText!);
              _bottomSheetVisible = false;
            });
          }
        },
        builder: (context, state) {
          final controller = state.controller;
          return Scaffold(
            backgroundColor: const Color(0xFF0B1220),
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              title: const Text("Capture License Plate"),
              centerTitle: true,
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.turn_left_rounded),
                onPressed: () {
                  _bloc.add(StopCaptureCamera());
                  Navigator.maybePop(context);
                },
              ),
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                const _GradientBackground(),
                if (state.isCameraReady &&
                    controller != null &&
                    controller.value.isInitialized)
                  _CameraLayer(controller: controller)
                else
                  const _IdleLayer(),
                const _FocusOverlay(),
                Positioned(
                  top: kToolbarHeight + 40,
                  left: 20,
                  right: 20,
                  child: _HudStatus(
                    processing: state.isProcessing,
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
                    child: _captureButton(
                      isProcessing: state.isProcessing,
                      onTap: _capture,
                    ),
                  ),
                ),
                if (_flash)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: _flash ? 1 : 0,
                    child: Container(color: Colors.white),
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

  Future<void> _showSaveBottomSheet(BuildContext context, String text) async {
    await showModalBottomSheet<void>(
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
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
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
                        if (!existing.contains(text)) {
                          existing.add(text);
                          await box.put('data', existing);
                          _savedPlates.add(text);
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
                        side: const BorderSide(color: Colors.white24, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Center(
                child: Text(
                  "📷 Kamera akan lanjut otomatis",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GradientBackground extends StatelessWidget {
  const _GradientBackground();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    ),
  );
}

class _CameraLayer extends StatelessWidget {
  final CameraController controller;
  const _CameraLayer({required this.controller});
  @override
  Widget build(BuildContext context) => Center(
    child: CameraPreview(controller),
  );
}

class _IdleLayer extends StatelessWidget {
  const _IdleLayer();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.camera_alt_outlined, color: Colors.white60, size: 50),
        SizedBox(height: 6),
        Text(
          'Arahkan kamera & tekan Capture',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
      ],
    ),
  );
}

class _FocusOverlay extends StatelessWidget {
  const _FocusOverlay();
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: Container(
        width: MediaQuery.sizeOf(context).width * 0.78,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.28), width: 1.6),
        ),
      ),
    ),
  );
}

class _HudStatus extends StatelessWidget {
  final bool processing;
  final String? message;
  const _HudStatus({required this.processing, this.message});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white.withOpacity(0.08),
        child: Row(
          children: [
            Icon(
              processing ? Icons.timelapse_rounded : Icons.camera_alt_rounded,
              color: processing ? Colors.orangeAccent : Colors.lightGreenAccent,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message ?? (processing ? "Memproses..." : "Siap Capture"),
                style: const TextStyle(
                  color: Colors.white,
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

class _GpuHint extends StatelessWidget {
  const _GpuHint();
  @override
  Widget build(BuildContext context) => Opacity(
    opacity: 0.9,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          color: Colors.white.withOpacity(0.07),
          child: const Row(
            children: [
              Icon(Icons.memory_rounded, color: Colors.tealAccent, size: 25),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Gunakan perangkat dengan GPU/NNAPI/Metal agar proses lebih cepat.",
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

class _LastResultToast extends StatelessWidget {
  final String text;
  const _LastResultToast({required this.text});
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(14),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: Colors.black.withOpacity(0.45),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Hasil Capture Terakhir",
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

Widget _captureButton({
  required bool isProcessing,
  required VoidCallback onTap,
}) {
  final color = isProcessing ? Colors.orangeAccent : Colors.tealAccent;
  final label = isProcessing ? "Processing..." : "Capture";
  return GestureDetector(
    onTap: isProcessing ? null : onTap,
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
          Icon(Icons.camera_alt_rounded, size: 20, color: color),
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
