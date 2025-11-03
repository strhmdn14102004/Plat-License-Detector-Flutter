// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:camera/camera.dart';
import 'package:face_recognition/module/plat/plat_bloc.dart';
import 'package:face_recognition/module/plat/plat_event.dart';
import 'package:face_recognition/module/plat/plat_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';

class PlateCapturePage extends StatefulWidget {
  const PlateCapturePage({super.key});
  @override
  State<PlateCapturePage> createState() => _PlateCapturePageState();
}

class _PlateCapturePageState extends State<PlateCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  CameraDescription? _camera;
  bool _ready = false;
  bool _flash = false;
  late PlateBloc _bloc;
  final List<String> _savedPlates = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bloc = context.read<PlateBloc>();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    _camera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _controller = CameraController(
      _camera!,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    await _controller!.initialize();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();

    _bloc.add(StopCamera());
    super.dispose();
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() => _flash = true);
    await Future.delayed(const Duration(milliseconds: 120));
    setState(() => _flash = false);
    if (_camera != null) {
      _bloc.add(CaptureAndProcess(_camera!));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) async {
        if (didPop) {
          await _controller?.dispose();
          _bloc.add(StopCamera());
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1220),
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text("Capture Plat Nomor"),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.turn_left_rounded),
            onPressed: () async {
              await _controller?.dispose();
              _bloc.add(StopCamera());
              if (mounted) Navigator.maybePop(context);
            },
          ),
        ),
        body: !_ready
            ? const Center(child: CircularProgressIndicator())
            : BlocConsumer<PlateBloc, PlateState>(
                listener: (context, state) {
                  if (state.lastText != null &&
                      !state.isProcessing &&
                      state.isFromCapture) {
                    final cleanText = state.lastText!.trim().toUpperCase();
                    if (cleanText.isNotEmpty &&
                        !_savedPlates.contains(cleanText)) {
                      _bloc.add(ClearLastResult());
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _showSaveBottomSheet(context, cleanText);
                      });
                    } else {
                      _bloc.add(ClearLastResult());
                    }
                  }
                },
                builder: (context, state) {
                  if (_controller == null ||
                      !_controller!.value.isInitialized) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Colors.tealAccent,
                      ),
                    );
                  }

                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      _CameraPreview(controller: _controller!),
                      const _FocusOverlay(),
                      if (state.isProcessing && state.isFromCapture)
                        Container(
                          color: Colors.black.withOpacity(0.75),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(height: 18),
                                Text(
                                  "Mohon tunggu...\nGambar sedang diproses",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (_flash)
                        AnimatedOpacity(
                          duration: const Duration(milliseconds: 120),
                          opacity: _flash ? 1 : 0,
                          child: Container(color: Colors.white),
                        ),
                      Positioned(
                        bottom: 40,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: GestureDetector(
                            onTap: state.isProcessing ? null : _captureImage,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 26,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.tealAccent.withOpacity(0.16),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: Colors.tealAccent.withOpacity(0.9),
                                  width: 1.8,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.tealAccent.withOpacity(0.35),
                                    blurRadius: 18,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.camera_alt_rounded,
                                    color: Colors.tealAccent,
                                    size: 22,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    "Capture",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
      ),
    );
  }

  void _showSaveBottomSheet(BuildContext context, String plateText) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.92),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
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
              const SizedBox(height: 4),
              const Text(
                'Plat Nomor Terbaca',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24, width: 1),
                ),
                child: Text(
                  plateText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        'Simpan',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24, width: 1),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        Navigator.pop(ctx);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  "📷 Kamera akan lanjut otomatis",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.45),
                    fontSize: 12,
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

class _CameraPreview extends StatelessWidget {
  final CameraController controller;
  const _CameraPreview({required this.controller});
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scale = 1 / (controller.value.aspectRatio * size.aspectRatio);
    return Transform.scale(
      scale: scale,
      child: Center(child: CameraPreview(controller)),
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
