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

  String cleanPlateRaw(String raw) {
    raw = raw.toUpperCase();

    raw = raw.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');

    raw = raw.replaceAll(RegExp(r'\s+'), ' ');

    raw = raw.replaceAll("PLAT", "");
    raw = raw.replaceAll("PLATE", "");

    return raw.trim();
  }

  bool _looksLikePlate(String text) {
    final cleaned = cleanPlateRaw(text);
    if (cleaned.isEmpty) return false;

    final hasLetter = cleaned.contains(RegExp(r'[A-Z]'));
    final hasDigit = cleaned.contains(RegExp(r'[0-9]'));
    if (!hasLetter || !hasDigit) return false;

    final parts = cleaned.split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.length < 2) return false;

    return true;
  }

  String _pickBestFromRecognized(RecognizedText result) {
    String? best;
    int bestScore = -1;

    void consider(String src, {int weight = 1}) {
      final cleaned = cleanPlateRaw(src);
      if (cleaned.isEmpty) return;
      if (!_looksLikePlate(cleaned)) return;

      final letters = RegExp(r'[A-Z]').allMatches(cleaned).length;
      final digits = RegExp(r'[0-9]').allMatches(cleaned).length;

      final score =
          letters +
          digits +
          (letters > 0 ? 2 : 0) +
          (digits > 0 ? 2 : 0) +
          weight;

      if (score > bestScore) {
        bestScore = score;
        best = cleaned;
      }
    }

    for (final block in result.blocks) {
      for (final line in block.lines) {
        consider(line.text, weight: 3);
      }
    }

    consider(result.text, weight: 1);

    return best ?? cleanPlateRaw(result.text);
  }

  String normalizePlate(String raw) {
    raw = cleanPlateRaw(raw);
    if (raw.isEmpty) return "TIDAK TERBACA";

    final parts = raw.split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return "TIDAK TERBACA";

    String prefix = parts[0];
    String middle = parts.length > 1 ? parts[1] : "";
    String suffix = parts.length > 2 ? parts.sublist(2).join("") : "";

    prefix = prefix.replaceAll(RegExp(r'[^A-Z]'), '');
    middle = middle.replaceAll(RegExp(r'[^0-9]'), '');
    suffix = suffix.replaceAll(RegExp(r'[^A-Z]'), '');

    prefix = prefix
        .replaceAll("0", "O")
        .replaceAll("1", "I")
        .replaceAll("2", "Z")
        .replaceAll("4", "A")
        .replaceAll("5", "S")
        .replaceAll("8", "B");

    suffix = suffix
        .replaceAll("0", "O")
        .replaceAll("1", "I")
        .replaceAll("2", "Z")
        .replaceAll("4", "A")
        .replaceAll("5", "S")
        .replaceAll("6", "G")
        .replaceAll("8", "B");

    const validPrefix = {
      "A",
      "B",
      "D",
      "E",
      "F",
      "T",
      "Z",
      "G",
      "H",
      "K",
      "R",
      "AA",
      "AB",
      "AD",
      "AE",
      "N",
      "S",
      "W",
      "L",
      "M",
      "DK",
      "DR",
      "DH",
      "EA",
      "BA",
      "BB",
      "BD",
      "BE",
      "BG",
      "BH",
      "BK",
      "BL",
      "BM",
      "BN",
      "BP",
      "DA",
      "KB",
      "KH",
      "KT",
      "KU",
      "KX",
      "DB",
      "DD",
      "DM",
      "DN",
      "DT",
      "DW",
      "DC",
      "PA",
      "PB",
      "DE",
    };

    if (prefix.length > 2) prefix = prefix.substring(0, 2);

    if (!validPrefix.contains(prefix)) {
      if (prefix.isNotEmpty && validPrefix.contains(prefix[0])) {
        prefix = prefix[0];
      } else if (prefix.length > 1 && validPrefix.contains(prefix[1])) {
        prefix = prefix[1];
      } else {
        prefix = "B";
      }
    }

    if (middle.isEmpty) {
      middle = "1";
    } else if (middle.length > 4) {
      middle = middle.substring(0, 4);
    }

    if (suffix.isEmpty) {
      suffix = "A";
    } else if (suffix.length > 3) {
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

      final candidate = _pickBestFromRecognized(result);
      if (candidate.isEmpty) return "TIDAK TERBACA";

      final normalized = normalizePlate(candidate);
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
Baca plat nomor kendaraan Indonesia.
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

      String resultText = "";
      for (final p in response.candidates?.firstOrNull?.content?.parts ?? []) {
        if (p is gai.TextPart) resultText += p.text;
      }

      return cleanPlateRaw(resultText);
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
          return normalizePlate(gemini);
        }
      }

      debugPrint("⚠️ Gemini gagal → fallback MLKit...");
      final mlkit = await runMlKit(jpeg);
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
