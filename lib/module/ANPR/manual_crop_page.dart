// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:io';
import 'dart:typed_data';

import 'package:anpr/module/ANPR/anpr_bloc.dart';
import 'package:anpr/module/ANPR/anpr_event.dart';
import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ManualCropPage extends StatefulWidget {
  final String imagePath;
  final List<Offset> initialQuad;

  const ManualCropPage({
    super.key,
    required this.imagePath,
    required this.initialQuad,
  });

  @override
  State<ManualCropPage> createState() => _ManualCropPageState();
}

class _ManualCropPageState extends State<ManualCropPage> {
  final CropController _cropController = CropController();

  Uint8List? _imageBytes;
  bool _isCropping = false;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    final bytes = await File(widget.imagePath).readAsBytes();
    if (!mounted) return;
    setState(() => _imageBytes = bytes);
  }

  void _onCrop() {
    if (_isCropping) return;
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Crop Plat Nomor'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _imageBytes == null || _isCropping ? null : _onCrop,
            icon: const Icon(Icons.check_circle, color: Colors.greenAccent),
            label: const Text(
              'SCAN',
              style: TextStyle(
                color: Colors.greenAccent,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: _imageBytes == null
          ? const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            )
          : Column(
              children: [
                Expanded(
                  child: Crop(
                    controller: _cropController,
                    image: _imageBytes!,
                    interactive: true,
                    fixCropRect: true,

                    aspectRatio: 16 / 4,

                    willUpdateScale: (newScale) => newScale <= 6,

                    radius: 12,
                    cornerDotBuilder: (_, _) => const SizedBox.shrink(),

                    overlayBuilder: (context, rect) {
                      return CustomPaint(painter: _GridPainter());
                    },

                    initialRectBuilder: InitialRectBuilder.withBuilder((
                      viewport,
                      imageRect,
                    ) {
                      final width = viewport.width * 0.85;
                      final height = width / (16 / 4);

                      return Rect.fromCenter(
                        center: Offset(
                          viewport.center.dx,
                          viewport.center.dy * 1.15,
                        ),
                        width: width,
                        height: height,
                      );
                    }),

                    onCropped: (result) async {
                      switch (result) {
                        case CropSuccess(:final croppedImage):
                          final file = File(
                            widget.imagePath.replaceFirst(
                              '.jpg',
                              '_manual.jpg',
                            ),
                          );
                          await file.writeAsBytes(croppedImage);

                          context.read<AnprBloc>().add(
                            SubmitManualCropEvent(
                              imagePath: file.path,
                              quad: const [
                                Offset(0, 0),
                                Offset(1, 0),
                                Offset(1, 1),
                                Offset(0, 1),
                              ],
                            ),
                          );

                          if (mounted) Navigator.pop(context);

                        case CropFailure(:final cause):
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Crop gagal: $cause'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                      }

                      if (mounted) {
                        setState(() => _isCropping = false);
                      }
                    },
                  ),
                ),

                Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[900],
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline, color: Colors.white70, size: 20),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Geser & zoom hingga plat pas di dalam kotak, lalu tekan SCAN',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 1;

    final thirdW = size.width / 3;
    final thirdH = size.height / 3;

    canvas.drawLine(Offset(thirdW, 0), Offset(thirdW, size.height), paint);
    canvas.drawLine(
      Offset(thirdW * 2, 0),
      Offset(thirdW * 2, size.height),
      paint,
    );
    canvas.drawLine(Offset(0, thirdH), Offset(size.width, thirdH), paint);
    canvas.drawLine(
      Offset(0, thirdH * 2),
      Offset(size.width, thirdH * 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}
