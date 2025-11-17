import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

class ModelManager {
  static const String settingsBoxName = 'settings';
  static const String _customModelKey = 'customModelPath';
  static const String defaultAssetModelPath =
      'assets/models/license_plate_detector_float16.tflite';

  final Box settingsBox;

  ModelManager(this.settingsBox);

  String? get customModelPath => settingsBox.get(_customModelKey) as String?;

  Future<void> setCustomModelPath(String path) async {
    await settingsBox.put(_customModelKey, path);
  }

  Future<void> clearCustomModelPath() async {
    await settingsBox.delete(_customModelKey);
  }

  Future<Uint8List> loadInitialModelBytes() async {
    final customPath = customModelPath;
    if (customPath != null) {
      final customBytes = await tryLoadCustomModel(customPath);
      if (customBytes != null) return customBytes;

      await clearCustomModelPath();
    }

    return loadDefaultModelBytes();
  }

  Future<Uint8List> loadDefaultModelBytes() async {
    final modelData = await rootBundle.load(defaultAssetModelPath);
    return modelData.buffer.asUint8List();
  }

  Future<Uint8List?> tryLoadCustomModel(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        if (bytes.isNotEmpty) return bytes;
      }
    } catch (_) {
      return null;
    }

    return null;
  }
}
