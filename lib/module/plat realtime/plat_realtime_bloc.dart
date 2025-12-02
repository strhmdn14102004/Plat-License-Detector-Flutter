// ignore_for_file: invalid_use_of_visible_for_testing_member, depend_on_referenced_packages

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as imglib;
import 'package:vehicle_identification_number/module/plat%20realtime/plat_realtime_event.dart';
import 'package:vehicle_identification_number/module/plat%20realtime/plat_realtime_state.dart';
import 'package:vehicle_identification_number/service/ocr_isolate_pool.dart';
import 'package:vehicle_identification_number/service/yolo_isolate_pool.dart';
import 'package:vehicle_identification_number/utils/plate_processing.dart';

class PlateRealtimeBloc extends Bloc<PlateRealtimeEvent, PlateRealtimeState> {
  final YoloIsolatePool yolo;
  final OcrIsolatePool ocr;

  bool _busy = false;

  PlateRealtimeBloc({required this.yolo, required this.ocr})
    : super(PlateRealtimeState.initial()) {
    on<InitializeRealtimeCamera>(_onInit);
    on<DisposeRealtimeCamera>(_onDispose);
    on<ChangeRealtimeFlash>(_onFlash);
  }

  Future<void> _onInit(
    InitializeRealtimeCamera ev,
    Emitter<PlateRealtimeState> emit,
  ) async {
    try {
      await state.controller?.dispose();

      final controller = CameraController(
        ev.camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isIOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );

      await controller.initialize();
      await controller.setFlashMode(state.flash);

      await controller.startImageStream(_processFrame);

      emit(
        PlateRealtimeState(
          isReady: true,
          isProcessing: false,
          controller: controller,
          text: null,
          flash: state.flash,
          cropped: null,
          fullFrame: null,
          message: "Kamera realtime aktif",
        ),
      );
    } catch (e) {
      emit(
        PlateRealtimeState(
          isReady: false,
          isProcessing: false,
          controller: null,
          text: null,
          flash: FlashMode.off,
          cropped: null,
          fullFrame: null,
          message: "⚠️ Kamera gagal dihidupkan",
        ),
      );
    }
  }

  Future<void> _processFrame(CameraImage frame) async {
    if (_busy) return;
    _busy = true;

    final jpeg = await _convertToJpeg(frame);
    if (jpeg == null) {
      _busy = false;
      return;
    }

    final det = await yolo.detect(jpeg);

    if (det.isEmpty) {
      emit(
        PlateRealtimeState(
          isReady: true,
          isProcessing: false,
          controller: state.controller,
          text: null,
          flash: state.flash,
          cropped: null,
          fullFrame: jpeg,
          message: "Mencari plat...",
        ),
      );
      _busy = false;
      return;
    }

    det.sort((a, b) => b.score.compareTo(a.score));
    final best = det.first;

    final rect = Rect.fromLTRB(
      best.x1.toDouble(),
      best.y1.toDouble(),
      best.x2.toDouble(),
      best.y2.toDouble(),
    );

    final cropped = await cropPlateRegion(jpeg, rect, marginFactor: 0.22);

    if (cropped == null) {
      _busy = false;
      return;
    }

    final text = await ocr.runMlKit(cropped);

    emit(
      PlateRealtimeState(
        isReady: true,
        isProcessing: false,
        controller: state.controller,
        text: text,
        flash: state.flash,
        cropped: cropped,
        fullFrame: jpeg,
        message: "Plat: $text",
      ),
    );

    _busy = false;
  }

  Future<Uint8List?> _convertToJpeg(CameraImage img) async {
    try {
      if (img.format.group == ImageFormatGroup.bgra8888) {
        final plane = img.planes[0];
        final bytes = plane.bytes;

        final buffer = bytes.buffer;

        final imglib.Image rgba = imglib.Image.fromBytes(
          width: img.width,
          height: img.height,
          bytes: buffer,

          numChannels: 4,
          order: imglib.ChannelOrder.bgra,
          format: imglib.Format.uint8,
        );

        final jpg = imglib.encodeJpg(rgba, quality: 90);
        return Uint8List.fromList(jpg);
      }

      final rgb = _convertYuv420(img);
      if (rgb == null) return null;

      return Uint8List.fromList(imglib.encodeJpg(rgb, quality: 90));
    } catch (_) {
      return null;
    }
  }

  imglib.Image? _convertYuv420(CameraImage img) {
    try {
      final width = img.width;
      final height = img.height;

      final y = img.planes[0].bytes;
      final u = img.planes[1].bytes;
      final v = img.planes[2].bytes;

      final out = imglib.Image(width: width, height: height);

      int index = 0;

      for (int yy = 0; yy < height; yy++) {
        for (int xx = 0; xx < width; xx++) {
          final yp = y[index];

          final uvIndex = (yy ~/ 2) * (width ~/ 2) + (xx ~/ 2);

          final up = u[uvIndex];
          final vp = v[uvIndex];

          final r = (yp + 1.370705 * (vp - 128)).clamp(0, 255).toInt();
          final g = (yp - 0.337633 * (up - 128) - 0.698001 * (vp - 128))
              .clamp(0, 255)
              .toInt();
          final b = (yp + 1.732446 * (up - 128)).clamp(0, 255).toInt();

          out.setPixelRgba(xx, yy, r, g, b, 255);

          index++;
        }
      }

      return out;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onFlash(
    ChangeRealtimeFlash ev,
    Emitter<PlateRealtimeState> emit,
  ) async {
    await state.controller?.setFlashMode(ev.mode);

    emit(
      PlateRealtimeState(
        isReady: state.isReady,
        isProcessing: state.isProcessing,
        controller: state.controller,
        text: state.text,
        flash: ev.mode,
        cropped: state.cropped,
        fullFrame: state.fullFrame,
        message: "Flash: ${ev.mode.name}",
      ),
    );
  }

  Future<void> _onDispose(
    DisposeRealtimeCamera ev,
    Emitter<PlateRealtimeState> emit,
  ) async {
    try {
      await state.controller?.dispose();
    } catch (_) {}

    emit(PlateRealtimeState.initial());
  }
}
