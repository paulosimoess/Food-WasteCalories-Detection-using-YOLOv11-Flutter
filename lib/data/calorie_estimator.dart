import 'dart:math';

class Detection {
  final String labelName;        // ex: "rice"
  final double confidence;       // 0..1
  final List<double>? bbox;      // [x1,y1,x2,y2]
  final double area;             // máscara se houver, senão bbox area

  Detection({
    required this.labelName,
    required this.confidence,
    required this.area,
    this.bbox,
  });
}

class EstimateItem {
  final String labelName;
  final double confidence;
  final int count;
  final double area;
  final double portionRatio;
  final double gramsEst;
  final double kcalPer100g;
  final double kcalEstimated;

  EstimateItem({
    required this.labelName,
    required this.confidence,
    required this.count,
    required this.area,
    required this.portionRatio,
    required this.gramsEst,
    required this.kcalPer100g,
    required this.kcalEstimated,
  });
}

class CalorieEstimator {
  static const Set<String> nonFood = {
    "plate", "knife", "fork", "spoon", "bowl", "cup",
    "garbage", "board", "water", "coffee", "coffee cup", "water cup"
  };

  static const Map<String, String> aliasLabels = {
    // "meatballs": "stewed veal",
  };

  static const Map<String, double> overridesKcal100g = {
    "rice": 130.0,
    "strawberry": 32.0,
    "vegetables": 35.0,
    "soup": 60.0,
    "chicken": 190.0,
  };

  static const Map<String, double> minConfByClass = {
    "pasta": 0.15,
    "soup": 0.25,
  };

  static const double minAreaFood = 1500.0;
  static const Map<String, double> minAreaByClass = {
    "pasta": 20000.0,
  };

  static const double maxPortion = 0.70;
  static const double maxGramsItem = 350.0;
  static const double minGramsItem = 10.0;
  static const double minConfDefault = 0.10;

  static const double areaSimilarity = 0.10;
  static const double iouThresh = 0.85;

  static const List<Set<String>> dedupFamilies = [
    {"rice", "pasta"},
    {"chips", "french fries"},
    {"steak", "grilled steak", "grilled chop"},
    {"meatballs", "minced meat", "stewed veal"},
    {"vegetables", "lettuce"},
  ];

  static const List<Set<String>> mutexGroups = [
    {"pasta", "soup"},
    {"rice", "soup"},
  ];
  static const double mutexIouThresh = 0.95;

  static const Map<String, int> classPriority = {
    "pasta": 3,
    "rice": 3,
    "soup": 1,
  };

  static const Map<String, double> fullPlateGrams = {
    "rice": 450.0,
    "pasta": 400.0,
    "french fries": 300.0,
    "chips": 300.0,
    "steak": 280.0,
    "grilled steak": 280.0,
    "grilled chop": 250.0,
    "vegetables": 250.0,
    "lettuce": 200.0,
    "soup": 350.0,
    "chicken": 300.0,
  };
  static const double defaultFullPlateGrams = 400.0;

  // helpers
  static String _normLabel(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r"\s+"), " ");

  static String _aliasLabel(String name) => aliasLabels[name] ?? name;

  static double _minConfFor(String name) => minConfByClass[name] ?? minConfDefault;

  static double _minAreaFor(String name) => minAreaByClass[name] ?? minAreaFood;

  static bool _hasValidBbox(Detection d) => d.bbox != null && d.bbox!.length == 4;

  static double _iou(List<double> a, List<double> b) {
    final ax1 = a[0], ay1 = a[1], ax2 = a[2], ay2 = a[3];
    final bx1 = b[0], by1 = b[1], bx2 = b[2], by2 = b[3];

    final interW = max(0.0, min(ax2, bx2) - max(ax1, bx1));
    final interH = max(0.0, min(ay2, by2) - max(ay1, by1));
    final inter = interW * interH;

    final areaA = max(0.0, ax2 - ax1) * max(0.0, ay2 - ay1);
    final areaB = max(0.0, bx2 - bx1) * max(0.0, by2 - by1);
    final union = areaA + areaB - inter;

    return union > 0 ? inter / union : 0.0;
  }

  static bool _sameFamily(String a, String b) {
    if (a == b) return true;
    for (final fam in dedupFamilies) {
      if (fam.contains(a) && fam.contains(b)) return true;
    }
    return false;
  }

  static bool _sameMutex(String a, String b) {
    for (final g in mutexGroups) {
      if (g.contains(a) && g.contains(b)) return true;
    }
    return false;
  }

  static bool _isFood(Detection d) {
    final name = _aliasLabel(_normLabel(d.labelName));
    if (name.isEmpty || nonFood.contains(name)) return false;

    final conf = d.confidence;
    final area = d.area;

    if (conf < _minConfFor(name)) return false;
    if (area <= 0 || area < _minAreaFor(name)) return false;

    return true;
  }

  static List<Detection> _dedupFood(List<Detection> objects) {
    final hasFoodBbox = objects.any((o) => _isFood(o) && _hasValidBbox(o));
    return hasFoodBbox ? _dedupFoodByIou(objects) : _dedupFoodBySimilarArea(objects);
  }

  static List<Detection> _dedupFoodByIou(List<Detection> objects) {
    final food = objects.where((o) => _isFood(o) && _hasValidBbox(o)).toList();
    if (food.isEmpty) return objects;

    food.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <Detection>[];

    for (final o in food) {
      final nameO = _aliasLabel(_normLabel(o.labelName));
      final confO = o.confidence;
      var ok = true;

      for (final k in List<Detection>.from(kept)) {
        final nameK = _aliasLabel(_normLabel(k.labelName));
        final confK = k.confidence;

        final isFam = _sameFamily(nameO, nameK);
        final isMut = _sameMutex(nameO, nameK);
        if (!isFam && !isMut) continue;

        final iou = _iou(o.bbox!, k.bbox!);

        // MUTEX
        if (isMut && iou >= mutexIouThresh) {
          final prO = classPriority[nameO] ?? 0;
          final prK = classPriority[nameK] ?? 0;

          if (prO < prK) {
            ok = false;
            break;
          }
          if (prO > prK) {
            kept.remove(k);
            continue;
          }
          if (confO <= confK) {
            ok = false;
            break;
          }
          kept.remove(k);
          continue;
        }

        // FAMILY
        if (isFam && iou >= iouThresh) {
          ok = false;
          break;
        }
      }

      if (ok) kept.add(o);
    }

    final keptSet = kept.toSet();
    final out = <Detection>[];
    for (final o in objects) {
      if (_isFood(o) && _hasValidBbox(o)) {
        if (keptSet.contains(o)) out.add(o);
      } else {
        out.add(o);
      }
    }
    return out;
  }

  static List<Detection> _dedupFoodBySimilarArea(List<Detection> objects) {
    final kept = <Detection>[];

    for (final obj in objects) {
      if (!_isFood(obj)) {
        kept.add(obj);
        continue;
      }

      final area = obj.area;
      final conf = obj.confidence;
      var merged = false;

      for (var i = 0; i < kept.length; i++) {
        final k = kept[i];
        if (!_isFood(k)) continue;

        final kArea = k.area;
        if (kArea <= 0) continue;

        final similarity = min(area, kArea) / max(area, kArea);
        if (similarity >= (1.0 - areaSimilarity)) {
          if (conf > k.confidence) kept[i] = obj;
          merged = true;
          break;
        }
      }

      if (!merged) kept.add(obj);
    }

    return kept;
  }

  static Map<String, _Agg> _aggregateByLabel(List<Detection> objects) {
    final agg = <String, _Agg>{};

    for (final o in objects) {
      final name = _aliasLabel(_normLabel(o.labelName));
      if (name.isEmpty || nonFood.contains(name)) continue;

      final conf = o.confidence;
      final area = o.area;

      if (conf < _minConfFor(name)) continue;
      if (area < _minAreaFor(name)) continue;

      agg.putIfAbsent(name, () => _Agg());
      agg[name]!.area += area;
      agg[name]!.conf = max(agg[name]!.conf, conf);
      agg[name]!.count += 1;
    }

    return agg;
  }

  static ({List<EstimateItem> items, double total}) estimate({
    required List<Detection> objects,
    required double plateArea,
    double garbageArea = 0.0,
    double gramsPerPlateFallback = 500.0,
    required Map<String, double> kcalBase, // calorie_map.json
  }) {
    final items = <EstimateItem>[];
    var total = 0.0;

    final plateUsable = max(1.0, plateArea - garbageArea);

    // dedup
    final deduped = _dedupFood(objects);

    // aggregate
    final agg = _aggregateByLabel(deduped);
    if (agg.isEmpty) return (items: <EstimateItem>[], total: 0.0);

    // raw portions
    final rawPortions = <String, double>{};
    for (final e in agg.entries) {
      rawPortions[e.key] = max(0.0, e.value.area / plateUsable);
    }

    // normalização se sum > 1
    final sumRaw = rawPortions.values.fold<double>(0.0, (a, b) => a + b);
    final scale = sumRaw > 1.0 ? (1.0 / sumRaw) : 1.0;

    final fallbackFullPlate = gramsPerPlateFallback > 0
        ? gramsPerPlateFallback
        : defaultFullPlateGrams;

    for (final entry in rawPortions.entries) {
      final name = entry.key;

      var portion = entry.value * scale;
      portion = portion.clamp(0.0, maxPortion);

      final fullPlate = fullPlateGrams[name] ?? fallbackFullPlate;
      var grams = portion * fullPlate;
      grams = grams.clamp(minGramsItem, maxGramsItem);

      final kcal100g = overridesKcal100g[name] ?? (kcalBase[name] ?? 0.0);
      if (kcal100g <= 0) continue;

      final kcal = ((kcal100g / 100.0) * grams);
      final kcalFinal = _round(kcal, 2);

      items.add(
        EstimateItem(
          labelName: name,
          confidence: _round(agg[name]!.conf, 4),
          count: agg[name]!.count,
          area: _round(agg[name]!.area, 2),
          portionRatio: _round(portion, 4),
          gramsEst: _round(grams, 1),
          kcalPer100g: _round(kcal100g, 2),
          kcalEstimated: kcalFinal,
        ),
      );

      total += kcalFinal;
    }

    items.sort((a, b) => b.kcalEstimated.compareTo(a.kcalEstimated));
    return (items: items, total: _round(total, 2));
  }

  static double _round(double v, int decimals) {
    final p = pow(10.0, decimals).toDouble();
    return (v * p).roundToDouble() / p;
  }
}

class _Agg {
  double area = 0.0;
  double conf = 0.0;
  int count = 0;
}