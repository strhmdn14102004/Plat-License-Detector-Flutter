// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as imglib;
import 'package:vehicle_identification_number/module/plat gallery/plat_gallery_event.dart';
import 'package:vehicle_identification_number/module/plat gallery/plat_gallery_state.dart';
import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';
import 'package:vehicle_identification_number/service/yolo_isolate_pool.dart';
import 'package:vehicle_identification_number/utils/plate_processing.dart';

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

      final rect = Rect.fromLTRB(
        best.x1.toDouble(),
        best.y1.toDouble(),
        best.x2.toDouble(),
        best.y2.toDouble(),
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

      final cropped = await cropPlateRegion(jpg640, rect, marginFactor: 0.25);

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

      final text = await waitForOcrResult(
        ocr,
        cropped,
        timeout: const Duration(seconds: 5),
      );

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
}
