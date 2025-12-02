// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:vehicle_identification_number/module/plat_capture_mlkit/plat_capture_mlkit_bloc.dart';
import 'package:vehicle_identification_number/module/plat_capture_mlkit/plat_capture_mlkit_event.dart';
import 'package:vehicle_identification_number/module/plat_capture_mlkit/plat_capture_mlkit_state.dart';

class PlateMlkitCapturePage extends StatefulWidget {
  const PlateMlkitCapturePage({super.key});

  @override
  State<PlateMlkitCapturePage> createState() => _PlateMlkitCapturePageState();
}

class _PlateMlkitCapturePageState extends State<PlateMlkitCapturePage>
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

    context.read<PlateMlkitCaptureBloc>().ocr.start();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cams = await availableCameras();

    _camera = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );

    context.read<PlateMlkitCaptureBloc>().add(InitializeMlkitCamera(_camera!));
  }

  @override
  void dispose() {
    context.read<PlateMlkitCaptureBloc>().add(DisposeMlkitCamera());
    _animCtl.dispose();
    super.dispose();
  }

  void _onFlashTap(FlashMode current) {
    final next = _nextFlashMode(current);
    context.read<PlateMlkitCaptureBloc>().add(ChangeMlkitFlashMode(next));
  }

  FlashMode _nextFlashMode(FlashMode current) {
    switch (current) {
      case FlashMode.off:
        return FlashMode.auto;
      case FlashMode.auto:
        return FlashMode.torch;
      default:
        return FlashMode.off;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        context.read<PlateMlkitCaptureBloc>().add(DisposeMlkitCamera());
        await Future.delayed(const Duration(milliseconds: 150));
        return true;
      },
      child: BlocConsumer<PlateMlkitCaptureBloc, PlateMlkitCaptureState>(
        listener: (context, state) async {
          if (!state.isProcessing &&
              state.lastText != null &&
              state.preview != null) {
            await _showResult(context, state.lastText!);
            context.read<PlateMlkitCaptureBloc>().add(
              ResetMlkitCamera(_camera!),
            );
          }
        },
        builder: (context, state) {
          final controller = state.controller;
          final preview = state.preview;
          final flashMode = state.flashMode;

          return Scaffold(
            backgroundColor: const Color(0xFF0B1220),
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              title: const Text("Scanner ML Kit Only"),
              centerTitle: true,
            ),
            body: SafeArea(
              child: Stack(
                children: [
                  if (preview == null &&
                      controller != null &&
                      controller.value.isInitialized)
                    Positioned.fill(
                      child: FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.previewSize!.height,
                          height: controller.value.previewSize!.width,
                          child: CameraPreview(controller),
                        ),
                      ),
                    ),

                  if (preview != null)
                    Positioned.fill(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: Image.memory(
                          preview,
                          key: ValueKey(preview),
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
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
                      bottom: 60,
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
                    top: 16,
                    right: 16,
                    child: _FlashToggle(
                      mode: flashMode,
                      enabled: controller != null,
                      onTap: () => _onFlashTap(flashMode),
                    ),
                  ),

                  Positioned(
                    bottom: 5,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.camera_alt),
                        label: Text(
                          state.isProcessing
                              ? "Memproses..."
                              : "Ambil Foto (ML Kit)",
                        ),
                        onPressed: state.isReady && !state.isProcessing
                            ? () => context.read<PlateMlkitCaptureBloc>().add(
                                CaptureMlkitPhoto(),
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
            ),
          );
        },
      ),
    );
  }

  Future<void> _showResult(BuildContext context, String text) async {
    final outerContext = context;
    final normalized = text.trim();
    final textController = TextEditingController(text: normalized);
    final focusNode = FocusNode();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black.withOpacity(0.95),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final box = Hive.box('plates');
        final existing = List<String>.from(box.get('data', defaultValue: []));

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: ValueListenableBuilder(
            valueListenable: textController,
            builder: (_, value, _) {
              final current = value.text.trim();
              final canSave =
                  current.isNotEmpty &&
                  current.toLowerCase() != 'tidak terbaca' &&
                  current.toLowerCase() != 'error';

              final normalizedCurrent = current.toUpperCase();
              final alreadySaved = existing.contains(normalizedCurrent);

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
                        'Plat Terbaca (ML Kit)',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ),
                    const SizedBox(height: 12),

                    TextField(
                      controller: textController,
                      focusNode: focusNode,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.4,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.06),
                        hintText: 'Masukkan plat',
                        hintStyle: const TextStyle(color: Colors.white38),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Colors.white24),
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
                                    final toSave = normalizedCurrent;
                                    existing.add(toSave);
                                    await box.put('data', existing);

                                    if (mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(
                                        outerContext,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Plat $toSave disimpan',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white70,
                            ),
                            label: const Text(
                              'Tutup',
                              style: TextStyle(color: Colors.white70),
                            ),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(
                                color: Colors.white24,
                                width: 1,
                              ),
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
          ),
        );
      },
    );

    textController.dispose();
    focusNode.dispose();
  }
}

class _FlashToggle extends StatelessWidget {
  final FlashMode mode;
  final VoidCallback onTap;
  final bool enabled;

  const _FlashToggle({
    required this.mode,
    required this.onTap,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (mode) {
      FlashMode.auto => Icons.flash_auto_rounded,
      FlashMode.torch => Icons.flash_on_rounded,
      _ => Icons.flash_off_rounded,
    };

    final label = switch (mode) {
      FlashMode.auto => 'Auto',
      FlashMode.torch => 'On',
      _ => 'Off',
    };

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.amberAccent, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Flash $label',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
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
