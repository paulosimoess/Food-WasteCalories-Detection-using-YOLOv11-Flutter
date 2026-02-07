import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

class CalorieService {
  late final List<String> labels;               // index -> label
  late final Map<String, double> kcalPer100g;   // label -> kcal/100g

  Future<void> init() async {
    labels = await _loadLabels('assets/labels.txt');
    kcalPer100g = await _loadKcalMap('assets/calorie_map.json');
  }

  Future<List<String>> _loadLabels(String path) async {
    final txt = await rootBundle.loadString(path);
    return txt
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
  }

  Future<Map<String, double>> _loadKcalMap(String path) async {
    final txt = await rootBundle.loadString(path);
    final dynamic obj = jsonDecode(txt);

    final map = <String, double>{};
    if (obj is Map<String, dynamic>) {
      obj.forEach((k, v) {
        final key = k.toString().trim().toLowerCase();
        final val = (v is num) ? v.toDouble() : double.tryParse(v.toString());
        if (val != null) map[key] = val;
      });
    }
    return map;
  }

  String labelForIndex(int classIndex) {
    if (classIndex < 0 || classIndex >= labels.length) return 'unknown';
    return labels[classIndex];
  }

  double kcal100gForIndex(int classIndex) {
    final label = labelForIndex(classIndex).toLowerCase();
    return kcalPer100g[label] ?? 0.0;
  }
}