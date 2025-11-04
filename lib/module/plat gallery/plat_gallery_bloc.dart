// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:face_recognition/module/plat gallery/plat_gallery_event.dart';
import 'package:face_recognition/module/plat gallery/plat_gallery_state.dart';
import 'package:face_recognition/service/ocr_isolate_pool.dart';
import 'package:face_recognition/service/yolo_isolate_pool.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;

class PlateGalleryBloc extends Bloc<PlateGalleryEvent, PlateGalleryState> {
  final YoloIsolatePool yolo;
  final OcrIsolatePool ocr;

  PlateGalleryBloc({required this.yolo, required this.ocr})
    : super(
        PlateGalleryState(
          isProcessing: false,
          progress: 0.0,
          message: "Pilih gambar dari galeri",
          lastText: null,
          preview: null,
        ),
      ) {
    on<PickGalleryImage>(_onPick);
  }

  Future<void> _onPick(
    PickGalleryImage ev,
    Emitter<PlateGalleryState> emit,
  ) async {
    emit(
      PlateGalleryState(
        isProcessing: true,
        progress: 0.1,
        message: "🔧 Menyiapkan gambar...",
        lastText: null,
        preview: ev.imageBytes,
      ),
    );

    try {
      final original = imglib.decodeImage(ev.imageBytes);
      if (original == null) throw Exception("Gagal decode gambar");

      final fixed = imglib.bakeOrientation(original);

      final resized = imglib.copyResize(
        fixed,
        width: 640,
        height: 640,
        interpolation: imglib.Interpolation.linear,
      );

      final jpg640 = Uint8List.fromList(imglib.encodeJpg(resized, quality: 90));

      emit(
        PlateGalleryState(
          isProcessing: true,
          progress: 0.25,
          message: "🔍 Mendeteksi plat...",
          lastText: null,
          preview: jpg640,
        ),
      );

      final result = await yolo.detect(jpg640);
      debugPrint("📦 YOLO detect result count: ${result.length}");

      if (result.isEmpty) {
        emit(
          PlateGalleryState(
            isProcessing: false,
            progress: 1.0,
            message: "❌ Plat tidak ditemukan",
            lastText: "Tidak terbaca",
            preview: jpg640,
          ),
        );
        return;
      }

      result.sort((a, b) => b.score.compareTo(a.score));
      final best = result.first;

      final rect = Rect.fromLTWH(
        best.x1.toDouble(),
        best.y1.toDouble(),
        (best.x2 - best.x1).toDouble(),
        (best.y2 - best.y1).toDouble(),
      );

      emit(
        PlateGalleryState(
          isProcessing: true,
          progress: 0.5,
          message: "✂️ Memotong area plat...",
          lastText: null,
          preview: jpg640,
        ),
      );

      final cropped = await compute(_cropIsolate, {
        'jpeg': jpg640,
        'rect': rect,
      });

      if (cropped == null) {
        emit(
          PlateGalleryState(
            isProcessing: false,
            progress: 1.0,
            message: "❌ Gagal crop gambar",
            lastText: "Tidak terbaca",
            preview: jpg640,
          ),
        );
        return;
      }

      emit(
        PlateGalleryState(
          isProcessing: true,
          progress: 0.7,
          message: "🧠 Memproses OCR...",
          lastText: null,
          preview: cropped,
        ),
      );

      String bestText = "";
      final sub = ocr.results.listen((t) {
        if (t.isNotEmpty && t.length > bestText.length) bestText = t;
      });

      ocr.push(cropped);

      final limit = DateTime.now().add(const Duration(seconds: 5));
      while (DateTime.now().isBefore(limit)) {
        await Future.delayed(const Duration(milliseconds: 200));
      }
      await sub.cancel();

      final text = bestText.trim();

      emit(
        PlateGalleryState(
          isProcessing: false,
          progress: 1.0,
          message: text.isEmpty ? "⚠️ Tidak terbaca" : "✅ Plat: $text",
          lastText: text.isEmpty ? "Tidak terbaca" : text,
          preview: cropped,
        ),
      );
    } catch (e, st) {
      debugPrint("❌ Error di PlateGalleryBloc: $e\n$st");
      emit(
        PlateGalleryState(
          isProcessing: false,
          progress: 1.0,
          message: "❌ Error: $e",
          lastText: "Error",
          preview: ev.imageBytes,
        ),
      );
    }
  }

  static Uint8List? _cropIsolate(Map<String, dynamic> args) {
    try {
      final jpeg = args['jpeg'] as Uint8List;
      final r = args['rect'] as Rect;

      final img = imglib.decodeImage(jpeg);
      if (img == null) return null;

      final x = r.left.clamp(0, img.width - 1).toInt();
      final y = r.top.clamp(0, img.height - 1).toInt();
      final w = (r.width.clamp(1, img.width - x)).toInt();
      final h = (r.height.clamp(1, img.height - y)).toInt();

      final cropped = imglib.copyCrop(img, x: x, y: y, width: w, height: h);
      return Uint8List.fromList(imglib.encodeJpg(cropped, quality: 95));
    } catch (_) {
      return null;
    }
  }
}
