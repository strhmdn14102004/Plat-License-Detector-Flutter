// ignore_for_file: unrelated_type_equality_checks

import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:googleai_dart/googleai_dart.dart' as gai;
import 'package:path_provider/path_provider.dart';

class OcrIsolatePool {
  static const String _apiKey = "AIzaSyAaXIBhfrhi2lwwiekFdTsdKt-8RWVCZGI";

  late final gai.GoogleAIClient _client;

  final _queue = StreamController<_OcrJob>();
  final _onResult = StreamController<String>.broadcast();
  bool _running = false;

  final _textRecognizer = TextRecognizer();

  Stream<String> get results => _onResult.stream;

  OcrIsolatePool() {
    _client = gai.GoogleAIClient(
      config: const gai.GoogleAIConfig(
        authProvider: gai.ApiKeyProvider(_apiKey),
      ),
    );
  }

  void start() {
    if (_running) return;
    _running = true;

    _queue.stream.asyncMap(_process).listen((text) {
      if (text != null && text.isNotEmpty) {
        _onResult.add(text);
      }
    });
  }

  void pushFull(Uint8List jpeg) => _queue.add(_OcrJob(jpeg, true));
  void pushCrop(Uint8List jpeg) => _queue.add(_OcrJob(jpeg, false));

  Future<bool> _hasInternet() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (_) {
      return false;
    }
  }

  String _clean(String raw) {
    return raw
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), '')
        .replaceAll("PLAT", "")
        .replaceAll("PLATE", "")
        .trim()
        .toUpperCase();
  }

  String normalizePlate(String raw) {
    raw = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9 ]'), '');

    final parts = raw.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) return raw;

    String prefix = parts[0];
    String middle = parts.length > 1 ? parts[1] : "";
    String suffix = parts.length > 2 ? parts.sublist(2).join("") : "";

    prefix = prefix.replaceAll(RegExp(r'[^A-Z]'), '');
    if (prefix.length > 2) prefix = prefix.substring(0, 2);

    middle = middle.replaceAll(RegExp(r'[^0-9]'), '');
    if (middle.length > 4) middle = middle.substring(0, 4);

    suffix = suffix.replaceAll(RegExp(r'[^A-Z]'), '');
    if (suffix.length > 3) suffix = suffix.substring(0, 3);

    if (suffix.isEmpty) suffix = "A";

    if (raw.length > 15) {
      raw = raw.substring(0, 15);
    }

    if (suffix.length > 3) {
      suffix = suffix.substring(0, 3);
    }

    return "$prefix $middle $suffix".trim();
  }

  Future<String> runMlKit(Uint8List jpegBytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = io.File("${dir.path}/ocr_mlkit.jpg");

      await file.writeAsBytes(jpegBytes);

      final input = InputImage.fromFilePath(file.path);

      final result = await _textRecognizer.processImage(input);
      final rawText = result.text.trim();

      if (rawText.isEmpty) return "TIDAK TERBACA";

      final cleaned = _clean(rawText);
      final normalized = normalizePlate(cleaned);

      return normalized;
    } catch (e) {
      debugPrint("❌ MLKit OCR Error: $e");
      return "TIDAK TERBACA";
    }
  }

  Future<String> _runGemini(Uint8List jpeg) async {
    try {
      final base64Image = base64Encode(jpeg);

      final response = await _client.models.generateContent(
        model: "gemini-2.5-flash",
        request: gai.GenerateContentRequest(
          contents: [
            gai.Content(
              role: "user",
              parts: [
                gai.TextPart("""
Baca plat nomor kendaraan pada gambar.
Jawab hanya format plat Indonesia.
Jika tidak terbaca: TIDAK TERBACA
"""),
                gai.InlineDataPart(
                  gai.Blob(mimeType: "image/jpeg", data: base64Image),
                ),
              ],
            ),
          ],
        ),
      );

      String result = "";
      for (final p in response.candidates?.firstOrNull?.content?.parts ?? []) {
        if (p is gai.TextPart) {
          result += p.text;
        }
      }

      return _clean(result);
    } catch (_) {
      return "TIDAK TERBACA";
    }
  }

  Future<String?> _process(_OcrJob job) async {
    try {
      final jpeg = job.jpeg;

      final online = await _hasInternet();

      if (online) {
        final gemini = await _runGemini(jpeg);

        if (gemini != "TIDAK TERBACA" && gemini.length >= 5) {
          debugPrint("✨ OCR via Gemini: $gemini");
          return gemini;
        }

        debugPrint("⚠️ Gemini gagal → fallback MLKit...");
      }

      final mlkit = await runMlKit(jpeg);
      debugPrint("📱 OCR via ML Kit: $mlkit");
      return mlkit;
    } catch (e, st) {
      debugPrint("❌ OCR PROCESS ERROR: $e\n$st");
      return "TIDAK TERBACA";
    }
  }

  void dispose() {
    _client.close();
    _textRecognizer.close();
    _queue.close();
    _onResult.close();
  }
}

class _OcrJob {
  final Uint8List jpeg;
  final bool full;
  _OcrJob(this.jpeg, this.full);
}
