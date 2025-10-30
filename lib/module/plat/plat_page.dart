// ignore_for_file: use_build_context_synchronously, deprecated_member_use

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
  final List<String> _savedPlates = [];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCameras().then((_) {
      if (_selectedCamera != null) {
        Future.delayed(const Duration(milliseconds: 400), () {
          context.read<PlateBloc>().add(StartCamera(_selectedCamera!));
          setState(() => _scanning = true);
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context.read<PlateBloc>().add(StopCamera());
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) super.dispose();
    });
  }

  Future<void> _loadCameras() async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      final cameras = await availableCameras();
      _selectedCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint("Camera error: $e");
    }
  }

  void _startScan() async {
    if (_selectedCamera == null) return;
    await Future.delayed(const Duration(milliseconds: 100));
    context.read<PlateBloc>().add(StartCamera(_selectedCamera!));
    setState(() => _scanning = true);
  }

  void _stopScan() {
    context.read<PlateBloc>().add(StopCamera());
    setState(() => _scanning = false);
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlateBloc, PlateState>(
      listener: (context, state) {
        if (state.lastText != null) {
          final text = state.lastText!.trim();
          final lines = text.split('\n');
          final plateRegex = RegExp(r'^[A-Z]{1,2}\s?\d{1,4}\s?[A-Z]{0,3}$');
          final hasPlate = lines.any((l) => plateRegex.hasMatch(l));
          if (hasPlate && !_savedPlates.contains(text)) {
            _showSaveBottomSheet(context, text);
          }
        }
      },
      builder: (context, state) {
        final controller = state.controller;
        return Scaffold(
          backgroundColor: Colors.black,
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            title: const Text("License Plate Scanner"),
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
          ),
          body: !_initialized
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_scanning &&
                        state.isCameraReady &&
                        controller != null &&
                        controller.value.isInitialized)
                      _buildCameraPreview(controller, state)
                    else
                      _buildIdlePlaceholder(),
                    Positioned(
                      bottom: 50,
                      left: 0,
                      right: 0,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _circleButton(
                            icon: Icons.play_arrow_rounded,
                            color: Colors.greenAccent,
                            onTap: _scanning ? null : _startScan,
                          ),
                          const SizedBox(width: 30),
                          _circleButton(
                            icon: Icons.stop_rounded,
                            color: Colors.redAccent,
                            onTap: _scanning ? _stopScan : null,
                          ),
                          const SizedBox(width: 30),
                          _circleButton(
                            icon: Icons.camera_alt_rounded,
                            color: Colors.blueAccent,
                            onTap: _scanning
                                ? () => context.read<PlateBloc>().add(
                                    ManualScanTrigger(),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    ),
                    if (_savedPlates.isNotEmpty)
                      Positioned(
                        bottom: 140,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 400),
                            padding: const EdgeInsets.all(14),
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.15),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent.withOpacity(0.2),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'Hasil Scan Terakhir',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _savedPlates.last,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                    letterSpacing: 1.1,
                                  ),
                                ),
                              ],
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

  Widget _circleButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 70,
        width: 70,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.white10 : color.withOpacity(0.2),
          shape: BoxShape.circle,
          border: Border.all(
            color: onTap == null ? Colors.white24 : color.withOpacity(0.9),
            width: 2,
          ),
          boxShadow: [
            if (onTap != null)
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 15,
                spreadRadius: 2,
              ),
          ],
        ),
        child: Icon(
          icon,
          color: onTap == null ? Colors.white30 : color,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildCameraPreview(CameraController controller, PlateState state) {
    final previewSize = controller.value.previewSize!;
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: previewSize.height,
                height: previewSize.width,
                child: CameraPreview(controller),
              ),
            ),
          ),
        ),
        if (state.lastBox != null)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            left: state.lastBox!.left,
            top: state.lastBox!.top,
            width: state.lastBox!.width,
            height: state.lastBox!.height,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.greenAccent.withOpacity(0.9),
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.greenAccent.withOpacity(0.3),
                    blurRadius: 15,
                    spreadRadius: 3,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildIdlePlaceholder() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined, color: Colors.white54, size: 100),
            SizedBox(height: 16),
            Text(
              'Tekan tombol Start untuk memulai scan',
              style: TextStyle(color: Colors.white70, fontSize: 16),
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
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('Simpan'),
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
                          setState(() => _savedPlates.add(plateText));
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
