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

    raw = raw.replaceAll("MASA BERLAKU", "");
    raw = raw.replaceAll("BERLAKU", "");
    raw = raw.replaceAll("BERL", "");
    raw = raw.replaceAll("PLAT", "");
    raw = raw.replaceAll("PLATE", "");

    return raw.trim();
  }

  String extractPlateCore(String raw) {
    raw = cleanPlateRaw(raw);
    final tokens = raw.split(' ').where((e) => e.isNotEmpty).toList();

    if (tokens.length < 2) return raw;

    tokens.removeWhere((t) => RegExp(r'^[0-9]{2}$').hasMatch(t));
    tokens.removeWhere((t) => RegExp(r'^[0-9]{2,4}$').hasMatch(t));

    if (tokens.length < 2) return raw;

    if (!RegExp(r'^[A-Z]{1,2}$').hasMatch(tokens[0])) return raw;

    final middle = tokens[1].replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^[0-9]{1,4}$').hasMatch(middle)) return raw;

    String suffix = "";
    if (tokens.length >= 3) {
      final s = tokens[2].replaceAll(RegExp(r'[^A-Z0-9]'), '');
      if (RegExp(r'^[A-Z0-9]{1,3}$').hasMatch(s)) suffix = s;
    }

    return suffix.isEmpty
        ? "${tokens[0]} $middle"
        : "${tokens[0]} $middle $suffix";
  }

  bool _looksLikePlate(String text) {
    text = extractPlateCore(text);
    final parts = text.split(' ').where((e) => e.isNotEmpty).toList();
    return parts.length >= 2;
  }

  String _pickBestFromRecognized(RecognizedText result) {
    String? best;
    int bestScore = -1;

    void consider(String src, {int weight = 1}) {
      final cleaned = extractPlateCore(src);
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

  String fixQHeuristic(String suffix) {
    if (suffix.isEmpty) return suffix;

    String s = suffix.toUpperCase();

    if (s == "OO") return "QO";

    if (RegExp(r'^[A-Z]{2}O$').hasMatch(s)) {
      return "${s.substring(0, 2)}Q";
    }

    if (s.length == 1 && s == "O") return "Q";

    if (s.endsWith("0")) {
      return "${s.substring(0, s.length - 1)}Q";
    }

    if (s == "O0") return "QO";

    return s;
  }

  String fixSuffix(String suffix) {
    if (suffix.isEmpty) return "";

    String s = suffix.toUpperCase();

    s = s.replaceAll("0", "O");
    s = s.replaceAll("1", "I");
    s = s.replaceAll("8", "B");
    s = s.replaceAll("6", "G");

    return s;
  }

  String normalizePlate(String raw, {bool fromGemini = false}) {
    raw = cleanPlateRaw(raw);
    raw = extractPlateCore(raw);

    final parts = raw.split(" ");
    if (parts.length < 2) return raw;

    final prefix = parts[0].replaceAll(RegExp(r'[^A-Z]'), '');
    final middle = parts[1].replaceAll(RegExp(r'[^0-9]'), '');

    String suffix = "";
    if (parts.length >= 3) {
      suffix = fixSuffix(parts[2]);
      suffix = fixQHeuristic(suffix);
    }

    return suffix.isEmpty ? "$prefix $middle" : "$prefix $middle $suffix";
  }

  Future<String> runMlKit(Uint8List jpegBytes) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = io.File("${dir.path}/ocr_mlkit.jpg");
      await file.writeAsBytes(jpegBytes);

      final input = InputImage.fromFilePath(file.path);
      final result = await _textRecognizer.processImage(input);

      final candidate = _pickBestFromRecognized(result);
      if (candidate.isEmpty) return "DUH GAKEBACA NIH MAS FELIX :(";

      return normalizePlate(candidate, fromGemini: false);
    } catch (e) {
      debugPrint("❌ MLKit OCR Error: $e");
      return "DUH GAKEBACA NIH MAS FELIX :(";
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
Ambil HANYA plat nomor Indonesia (huruf + angka + suffix).
Abaikan masa berlaku atau teks lain.
Jika tidak terbaca → DUH GAKEBACA NIH MAS FELIX :(
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
      return "DUH GAKEBACA NIH MAS FELIX :(";
    }
  }

  Future<String?> _process(_OcrJob job) async {
    try {
      final jpeg = job.jpeg;

      final online = await _hasInternet();
      if (online) {
        final gem = await _runGemini(jpeg);

        if (gem != "DUH GAKEBACA NIH MAS FELIX :(" && gem.length >= 4) {
          debugPrint("✨ Gemini RAW: $gem");
          return normalizePlate(gem, fromGemini: true);
        }
      }

      debugPrint("⚠️ Gemini gagal → fallback MLKit");
      return await runMlKit(jpeg);
    } catch (e, st) {
      debugPrint("❌ OCR PROCESS ERROR: $e\n$st");
      return "DUH GAKEBACA NIH MAS FELIX :(";
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
