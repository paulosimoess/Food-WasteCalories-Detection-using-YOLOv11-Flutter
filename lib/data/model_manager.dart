import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ModelManager {
  static const String zipUrl =
      'https://github.com/paulosimoess/Food-WasteCalories-Detection-using-YOLOv11-Flutter/releases/download/0.0.1-model-only/models_asset.zip';

  static const String version = '0.0.1-model-only';
  static const String _prefsKey = 'model_assets_version';

  static Future<String> ensureModelPath() async {
    final prefs = await SharedPreferences.getInstance();
    final docs = await getApplicationDocumentsDirectory();

    final baseDir = Directory('${docs.path}/model_assets/$version');
    if (!await baseDir.exists()) await baseDir.create(recursive: true);

    // tenta reutilizar se já foi instalado
    if (prefs.getString(_prefsKey) == version) {
      final existing = _findTflite(baseDir);
      if (existing != null) return existing;
    }

    // download
    final resp = await http.get(Uri.parse(zipUrl));
    if (resp.statusCode != 200) {
      throw Exception('Falha no download do ZIP: HTTP ${resp.statusCode}');
    }

    // limpa pasta
    for (final e in baseDir.listSync()) {
      try { e.deleteSync(recursive: true); } catch (_) {}
    }

    // unzip
    final archive = ZipDecoder().decodeBytes(resp.bodyBytes);
    for (final f in archive) {
      if (!f.isFile) continue;
      final name = f.name.split('/').last;
      final out = File('${baseDir.path}/$name');
      final data = f.content as List<int>;
      await out.writeAsBytes(Uint8List.fromList(data), flush: true);
    }

    final modelPath = _findTflite(baseDir);
    if (modelPath == null) {
      final files = baseDir
          .listSync()
          .whereType<File>()
          .map((f) => f.path.split(Platform.pathSeparator).last)
          .toList();
      throw Exception('ZIP extraído mas não encontrei .tflite. Ficheiros: $files');
    }

    await prefs.setString(_prefsKey, version);
    return modelPath;
  }

  static String? _findTflite(Directory dir) {
    for (final e in dir.listSync()) {
      if (e is File && e.path.toLowerCase().endsWith('.tflite')) return e.path;
    }
    return null;
  }
}