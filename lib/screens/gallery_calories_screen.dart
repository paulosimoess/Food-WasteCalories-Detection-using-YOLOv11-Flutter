import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:ultralytics_yolo/yolo.dart';

import '../data/calorie_estimator.dart';
import '../data/calorie_service.dart';
import '../data/model_manager.dart';

class GalleryCaloriesScreen extends StatefulWidget {
  const GalleryCaloriesScreen({super.key});

  @override
  State<GalleryCaloriesScreen> createState() => _GalleryCaloriesScreenState();
}

class _GalleryCaloriesScreenState extends State<GalleryCaloriesScreen> {
  final _picker = ImagePicker();
  final _calorieService = CalorieService();

  YOLO? _yolo;
  bool _loadingModel = true;
  bool _running = false;

  File? _imageFile;

  double totalKcal = 0.0;
  bool plateDetected = false;
  int detectionsCount = 0;

  // Guarda itens detalhados para mostrar confidence/grams
  List<EstimateItem> _items = [];

  // Para fallback quando não há plate
  int _imgW = 0;
  int _imgH = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _calorieService.init();

      final modelPath = await ModelManager.ensureModelPath();

      // Se o modelo for de segmentação, o filename muitas vezes contém "seg"
      final isSeg = modelPath.toLowerCase().contains('seg');

      _yolo = YOLO(
        modelPath: modelPath,
        task: isSeg ? YOLOTask.segment : YOLOTask.detect,
      );
      await _yolo!.loadModel();
    } catch (e) {
      debugPrint('Init error: $e');
    } finally {
      if (mounted) setState(() => _loadingModel = false);
    }
  }

  Future<void> _pickFromGallery() async {
    // Reduzir o tamanho melhora bastante a inferência e evita falhas silenciosas
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 90,
    );
    if (picked == null) return;

    final file = File(picked.path);

    setState(() {
      _imageFile = file;
      totalKcal = 0.0;
      plateDetected = false;
      detectionsCount = 0;
      _items = [];
      _imgW = 0;
      _imgH = 0;
    });

    await _runOnImage(file);
  }

  Future<void> _runOnImage(File file) async {
    if (_yolo == null) return;

    setState(() => _running = true);

    try {
      final Uint8List bytes = await file.readAsBytes();

      // Lê dimensões da imagem (para fallback de plateArea)
      final ui.Image decoded = await _decodeImage(bytes);
      _imgW = decoded.width;
      _imgH = decoded.height;

      final dynamic raw = await _yolo!.predict(bytes);
      // debugPrint('RAW_PREDICT: $raw');

      final List<dynamic> boxes = _extractBoxes(raw);

      if (mounted) {
        setState(() => detectionsCount = boxes.length);
      }

      final detections = <Detection>[];

      double plateArea = 0.0;
      double garbageArea = 0.0;

      // Para construir um fallback melhor
      double totalFoodArea = 0.0;
      double biggestFoodArea = 0.0;
      int foodCount = 0;

      for (final b in boxes) {
        if (b is! Map) continue;

        final labelNorm = _extractLabel(b).trim().toLowerCase();
        final conf = _extractConfidence(b);
        final bbox = _extractBbox(b);

        if (bbox == null) continue;

        final x1 = bbox[0], y1 = bbox[1], x2 = bbox[2], y2 = bbox[3];
        final bboxArea = (x2 - x1).abs() * (y2 - y1).abs();

        final det = Detection(
          labelName: labelNorm,
          confidence: conf,
          area: bboxArea,
          bbox: [x1, y1, x2, y2],
        );
        detections.add(det);

        if (labelNorm == 'plate') plateArea += bboxArea;
        if (labelNorm == 'garbage') garbageArea += bboxArea;

        // conta comida (usando a mesma regra do estimator: nonFood)
        if (!_isNonFood(labelNorm)) {
          // respeita thresholds base do estimator (evita lixo)
          if (conf >= CalorieEstimator.minConfDefault &&
              bboxArea >= CalorieEstimator.minAreaFood) {
            totalFoodArea += bboxArea;
            biggestFoodArea = biggestFoodArea < bboxArea ? bboxArea : biggestFoodArea;
            foodCount += 1;
          }
        }
      }

      final hasPlate = plateArea > 0;

      final imageArea = (_imgW > 0 && _imgH > 0) ? (_imgW * _imgH).toDouble() : 1.0;

      // ✅ Fallback inteligente:
      // - se não há plate, estimar plateArea como "comida ocupa ~45% do prato" (ajustável)
      // - clamped a [55% .. 90%] da imagem, para estabilidade
      final effectivePlateArea = hasPlate
          ? plateArea
          : _estimatePlateAreaFromFood(
              imageArea: imageArea,
              totalFoodArea: totalFoodArea,
              biggestFoodArea: biggestFoodArea,
              foodCount: foodCount,
            );

      final res = CalorieEstimator.estimate(
        objects: detections,
        plateArea: effectivePlateArea,
        garbageArea: garbageArea,
        gramsPerPlateFallback: 500.0,
        kcalBase: _calorieService.kcalPer100g,
      );

      if (mounted) {
        setState(() {
          plateDetected = hasPlate;
          totalKcal = res.total;
          _items = res.items;
        });
      }
    } catch (e) {
      debugPrint('Predict error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao processar imagem: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  // ---------- Fallback plateArea ----------

  bool _isNonFood(String label) => CalorieEstimator.nonFood.contains(label);

  double _estimatePlateAreaFromFood({
    required double imageArea,
    required double totalFoodArea,
    required double biggestFoodArea,
    required int foodCount,
  }) {
    // Defaults: se não há info, assume 70% da imagem como prato
    double plate = imageArea * 0.70;

    if (totalFoodArea > 0) {
      // Regra base:
      // comida ocupa tipicamente 35%~55% do prato numa foto "normal"
      // => plate ≈ totalFoodArea / 0.45
      plate = totalFoodArea / 0.45;

      // Se só há 1 deteção (ex: só arroz), geralmente a comida ocupa mais do prato
      // (mais "close-up") -> usar 0.60 para não inflacionar tanto
      if (foodCount <= 1) {
        plate = totalFoodArea / 0.60;
      }

      // Se a maior deteção ocupa quase tudo, também é provável ser close-up
      if (biggestFoodArea >= imageArea * 0.35) {
        plate = totalFoodArea / 0.65;
      }
    }

    // Clamp para estabilidade
    final minPlate = imageArea * 0.55;
    final maxPlate = imageArea * 0.90;

    if (plate < minPlate) plate = minPlate;
    if (plate > maxPlate) plate = maxPlate;

    return plate;
  }

  // ---------- Helpers ----------

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (img) => completer.complete(img));
    return completer.future;
  }

  List<dynamic> _extractBoxes(dynamic raw) {
    if (raw == null) return const [];

    if (raw is List) return raw;

    if (raw is Map) {
      for (final key in ['boxes', 'detections', 'predictions', 'data', 'results']) {
        final v = raw[key];
        if (v is List) {
          if (v.isNotEmpty && v.first is Map && (v.first as Map).containsKey('boxes')) {
            final inner = (v.first as Map)['boxes'];
            if (inner is List) return inner;
          }
          return v;
        }
      }

      final r = raw['result'];
      if (r is Map) {
        final b = r['boxes'];
        if (b is List) return b;
      }
    }

    return const [];
  }

  String _extractLabel(Map b) {
    final v1 = b['class'] ?? b['className'] ?? b['label'] ?? b['name'];

    if (v1 is String) return v1;
    if (v1 is num) return _calorieService.labelForIndex(v1.toInt());

    final v2 = b['classIndex'] ?? b['class_id'] ?? b['classId'];
    if (v2 is num) return _calorieService.labelForIndex(v2.toInt());

    return 'unknown';
  }

  double _extractConfidence(Map b) {
    final v = b['confidence'] ?? b['conf'] ?? b['score'];
    if (v is num) return v.toDouble();
    return 1.0;
  }

  List<double>? _extractBbox(Map b) {
    final bb = b['bbox'] ?? b['box'];
    if (bb is List && bb.length == 4) {
      final vals = bb.map((e) => (e as num).toDouble()).toList();

      // Pode vir como [x,y,w,h]
      final x = vals[0], y = vals[1], a = vals[2], d = vals[3];
      final looksLikeXywh = (a > 0 && d > 0) && (a < 20000 && d < 20000);
      if (looksLikeXywh && (x + a) > x && (y + d) > y) {
        return [x, y, x + a, y + d];
      }

      return vals;
    }

    final x1 = b['x1'] ?? b['left'];
    final y1 = b['y1'] ?? b['top'];
    final x2 = b['x2'] ?? b['right'];
    final y2 = b['y2'] ?? b['bottom'];

    if (x1 is num && y1 is num && x2 is num && y2 is num) {
      return [x1.toDouble(), y1.toDouble(), x2.toDouble(), y2.toDouble()];
    }

    final x = b['x'];
    final y = b['y'];
    final w = b['w'] ?? b['width'];
    final h = b['h'] ?? b['height'];

    if (x is num && y is num && w is num && h is num) {
      final xd = x.toDouble(), yd = y.toDouble(), wd = w.toDouble(), hd = h.toDouble();
      return [xd, yd, xd + wd, yd + hd];
    }

    return null;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Calorias por Imagem')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _loadingModel
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _running ? null : _pickFromGallery,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Escolher imagem da galeria'),
                  ),
                  const SizedBox(height: 12),

                  if (_imageFile != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(
                        _imageFile!,
                        height: 240,
                        fit: BoxFit.cover,
                      ),
                    ),

                  const SizedBox(height: 12),

                  if (_running) const LinearProgressIndicator(),

                  const SizedBox(height: 12),

                  Text(
                    'Kcal: ${totalKcal.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    plateDetected
                        ? 'Prato detetado ✅'
                        : 'Prato não detetado (fallback inteligente) ⚠️',
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 6),

                  Text(
                    'Deteções: $detectionsCount',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white54),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: _items.isEmpty
                        ? const Center(child: Text('Sem resultados ainda.'))
                        : ListView.builder(
                            itemCount: _items.length.clamp(0, 10),
                            itemBuilder: (context, i) {
                              final it = _items[i];
                              return ListTile(
                                title: Text(it.labelName),
                                subtitle: Text(
                                  'conf: ${it.confidence.toStringAsFixed(2)}  •  ${it.gramsEst.toStringAsFixed(0)} g  •  porção: ${(it.portionRatio * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(color: Colors.white54),
                                ),
                                trailing: Text('${it.kcalEstimated.toStringAsFixed(0)} kcal'),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}