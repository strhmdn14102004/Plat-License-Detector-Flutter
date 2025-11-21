import 'dart:async';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiOcrService {
  GeminiOcrService({required String apiKey})
      : _model = GenerativeModel(
          model: 'models/gemini-1.5-flash',
          apiKey: apiKey,
        );

  final GenerativeModel _model;

  Future<String> recognizePlate(Uint8List imageBytes) async {
    try {
      final prompt = Content.multi([
        TextPart(
          'Ekstrak teks nomor plat kendaraan dari gambar. '
          'Balas hanya dengan teks plat dalam huruf kapital tanpa penjelasan lain. '
          'Jika tidak yakin, balas "" (string kosong).',
        ),
        DataPart('image/jpeg', imageBytes),
      ]);

      final response = await _model.generateContent([prompt]);
      final rawText = response.text ?? '';
      return _normalizePlate(rawText);
    } catch (_) {
      return '';
    }
  }

  String _normalizePlate(String raw) {
    if (raw.isEmpty) return '';

    final firstLine = raw.split('\n').first;
    var cleaned = firstLine.toUpperCase();
    cleaned = cleaned.replaceAll(RegExp(r'[^A-Z0-9 ]'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ').trim();

    final match =
        RegExp(r'([A-Z]{1,3})\s*([0-9]{1,5})\s*([A-Z]{0,4})').firstMatch(cleaned);
    if (match != null) {
      final prefix = match.group(1) ?? '';
      final mid = match.group(2) ?? '';
      final suffix = match.group(3) ?? '';
      return '$prefix $mid $suffix'.trim();
    }

    return cleaned;
  }
}
