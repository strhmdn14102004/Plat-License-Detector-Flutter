// ignore_for_file: deprecated_member_use, use_build_context_synchronously, invalid_use_of_visible_for_testing_member

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:shimmer/shimmer.dart';

import 'plat_gallery_bloc.dart';
import 'plat_gallery_event.dart';
import 'plat_gallery_state.dart';

class PlateGalleryPage extends StatefulWidget {
  const PlateGalleryPage({super.key});

  @override
  State<PlateGalleryPage> createState() => _PlateGalleryPageState();
}

class _PlateGalleryPageState extends State<PlateGalleryPage>
    with SingleTickerProviderStateMixin {
  bool _bottomSheetVisible = false;
  final List<String> _savedPlates = [];
  late final AnimationController _animCtl;

  @override
  void initState() {
    super.initState();
    _animCtl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    Future.microtask(() {
      final bloc = context.read<PlateGalleryBloc>();
      bloc.stream.listen((s) {
        debugPrint(
          "📸 [GalleryBloc] emit: "
          "isProcessing=${s.isProcessing}, "
          "message=${s.message}, "
          "hasPreview=${s.preview != null}, "
          "lastText=${s.lastText}",
        );
      });
    });
  }

  @override
  void dispose() {
    _animCtl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (result == null) return;

    Uint8List? bytes = result.files.single.bytes;
    final path = result.files.single.path;

    if (bytes == null && path != null && await File(path).exists()) {
      bytes = await File(path).readAsBytes();
      debugPrint("📂 File dibaca manual dari path: ${p.basename(path)}");
    }

    if (bytes == null) {
      debugPrint("❌ Gagal membaca file gambar");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Gagal membaca file gambar")),
      );
      return;
    }

    final bloc = context.read<PlateGalleryBloc>();

    bloc.emit(
      PlateGalleryState(
        preview: bytes,
        isProcessing: true,
        progress: 0.0,
        message: '🔍 Scanning...',
        lastText: null,
      ),
    );

    _animCtl.forward(from: 0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint(
        "🎯 Mengirim PickGalleryImage event (${bytes!.lengthInBytes} bytes)",
      );
      bloc.add(PickGalleryImage(bytes));
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PlateGalleryBloc, PlateGalleryState>(
      listener: (context, state) async {
        if (!state.isProcessing &&
            state.lastText != null &&
            !_bottomSheetVisible) {
          _bottomSheetVisible = true;
          _animCtl.reverse();
          await _showBottomSheet(context, state.lastText!);
          _bottomSheetVisible = false;
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: const Color(0xFF0B1220),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text("Mode Galeri Scanner"),
            centerTitle: true,
          ),
          body: SafeArea(
            child: Stack(
              children: [
                if (state.preview != null)
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Center(
                      key: ValueKey(state.preview),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              state.preview!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            ),

                            if (state.isProcessing)
                              AnimatedBuilder(
                                animation: _animCtl,
                                builder: (context, _) => BackdropFilter(
                                  filter: ImageFilter.blur(
                                    sigmaX: 10 * _animCtl.value,
                                    sigmaY: 10 * _animCtl.value,
                                  ),
                                  child: Shimmer.fromColors(
                                    baseColor: Colors.tealAccent.withOpacity(
                                      0.25,
                                    ),
                                    highlightColor: Colors.white.withOpacity(
                                      0.1,
                                    ),
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
                else
                  const Center(
                    child: Text(
                      "Pilih gambar yang mengandung plat kendaraan",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70, fontSize: 15),
                    ),
                  ),

                if (state.isProcessing)
                  Positioned(
                    bottom: 110,
                    left: 50,
                    right: 50,
                    child: LinearProgressIndicator(
                      value: (state.progress > 0 && state.progress <= 1)
                          ? state.progress
                          : null,
                      color: Colors.tealAccent,
                      backgroundColor: Colors.white10,
                    ),
                  ),

                if (state.message != null)
                  Positioned(
                    bottom: 65,
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
                  bottom: 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.image_search_rounded),
                      label: Text(
                        state.isProcessing ? "Memproses..." : "Pilih Gambar",
                      ),
                      onPressed: state.isProcessing
                          ? null
                          : () => _pickImage(context),
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
    );
  }

  Future<void> _showBottomSheet(BuildContext context, String text) async {
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
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 22),
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
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white70,
                      ),
                      label: const Text(
                        'Tutup',
                        style: TextStyle(color: Colors.white70),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
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
