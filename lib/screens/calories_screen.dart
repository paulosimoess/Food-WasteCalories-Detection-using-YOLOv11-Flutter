import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../data/model_manager.dart';
import '../data/calorie_service.dart';
import '../data/calorie_estimator.dart';

class CaloriesScreen extends StatefulWidget {
  const CaloriesScreen({super.key});

  @override
  State<CaloriesScreen> createState() => _CaloriesScreenState();
}

class _CaloriesScreenState extends State<CaloriesScreen> {
  bool _isModelLoading = true;
  String? _modelPath;

  final _calorieService = CalorieService();
  bool _assetsReady = false;

  // UI state
  bool plateDetected = false;
  double totalKcal = 0.0;
  Map<String, double> kcalByLabel = {};
  int detectionsCount = 0;

  // throttle / protection
  bool _busy = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _processEvery = const Duration(milliseconds: 350);

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    setState(() => _isModelLoading = true);

    try {
      await _calorieService.init();
      final path = await ModelManager.ensureModelPath();
      if (!mounted) return;

      setState(() {
        _assetsReady = true;
        _modelPath = path;
        _isModelLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _assetsReady = false;
        _modelPath = null;
        _isModelLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro a preparar modelo/assets: $e')),
      );
    }
  }

  // Para calorias, segment ajuda muito porque dá maskArea (melhor para porções)
  static const YOLOStreamingConfig _streamingConfig = YOLOStreamingConfig.custom(
    includeOriginalImage: true, // IMPORTANT: evita ecrã preto
    includeDetections: true,
    includeMasks: true, // melhor para estimar áreas
    includeFps: false,
    includeProcessingTimeMs: false,
    includeClassifications: false,
    includePoses: false,
    includeOBB: false,
    maxFPS: 12,
    inferenceFrequency: 7,
    throttleInterval: Duration(milliseconds: 220),
  );

  void _handleResult(List<dynamic> data) {
    if (!_assetsReady) return;

    final now = DateTime.now();
    if (_busy) return;
    if (now.difference(_lastProcessed) < _processEvery) return;
    _lastProcessed = now;

    _busy = true;

    try {
      detectionsCount = data.length;

      final detections = <Detection>[];
      double plateArea = 0.0;
      double garbageArea = 0.0;

      double maxBBoxArea = 0.0;
      double foodAreaSum = 0.0;

      for (final object in data) {
        final x1 = object.boundingBox.left.toDouble();
        final y1 = object.boundingBox.top.toDouble();
        final x2 = object.boundingBox.right.toDouble();
        final y2 = object.boundingBox.bottom.toDouble();

        final bboxArea = (x2 - x1).abs() * (y2 - y1).abs();
        maxBBoxArea = max(maxBBoxArea, bboxArea);

        final label = _calorieService.labelForIndex(object.classIndex);
        final labelNorm = label.trim().toLowerCase();

        double conf = 1.0;
        try {
          final dynamic anyObj = object;
          final dynamic c = anyObj.confidence ?? anyObj.conf ?? anyObj.score;
          if (c is num) conf = c.toDouble();
        } catch (_) {
          conf = 1.0;
        }

        // area: maskArea se existir, senão bboxArea
        double usedArea = bboxArea;
        try {
          final dynamic anyObj = object;
          final dynamic m =
              anyObj.maskArea ?? anyObj.segmentationArea ?? anyObj.mask_area;
          if (m is num && m.toDouble() > 0) usedArea = m.toDouble();
        } catch (_) {
          usedArea = bboxArea;
        }

        detections.add(
          Detection(
            labelName: labelNorm,
            confidence: conf,
            area: usedArea,
            bbox: [x1, y1, x2, y2],
          ),
        );

        if (labelNorm == 'plate') plateArea += usedArea;
        if (labelNorm == 'garbage') garbageArea += usedArea;

        final isFood = !CalorieEstimator.nonFood.contains(labelNorm);
        if (isFood) foodAreaSum += usedArea;
      }

      final bool hasPlate = plateArea > 0;

      // ✅ fallback inteligente quando não há prato:
      // - se houver comida, assume que a comida ocupa ~35% do prato em média
      // - senão usa max bbox * 2.2 como “área de prato” aproximada
      final double effectivePlateArea = hasPlate
          ? plateArea
          : (foodAreaSum > 0
              ? (foodAreaSum / 0.35)
              : max(1.0, maxBBoxArea * 2.2));

      double newTotalKcal = 0.0;
      final newKcalByLabel = <String, double>{};

      final res = CalorieEstimator.estimate(
        objects: detections,
        plateArea: effectivePlateArea,
        garbageArea: garbageArea,
        gramsPerPlateFallback: 500.0,
        kcalBase: _calorieService.kcalPer100g,
      );

      newTotalKcal = res.total;

      for (final it in res.items) {
        newKcalByLabel[it.labelName] =
            (newKcalByLabel[it.labelName] ?? 0.0) + it.kcalEstimated;
      }

      if (!mounted) return;
      setState(() {
        plateDetected = hasPlate;
        totalKcal = newTotalKcal;
        kcalByLabel = newKcalByLabel;
        detectionsCount = data.length;
      });
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final top = kcalByLabel.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Deteção de Calorias'),
      ),
      body: Stack(
        children: [
          if (!_isModelLoading && _modelPath != null)
            YOLOView(
              modelPath: _modelPath!,
              task: YOLOTask.segment, // sempre segment, sem botão, sem trocar task
              streamingConfig: _streamingConfig,
              onResult: (data) => _handleResult(data),
            ),

          if (_isModelLoading) const Center(child: CircularProgressIndicator()),
          if (!_isModelLoading && _modelPath == null)
            const Center(child: Text('Falha a carregar o modelo.')),

          // HUD calorias
          Positioned(
            top: 20,
            left: 20,
            child: _HudBox(
              child: Text(
                'Kcal: ${totalKcal.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Positioned(
            top: 78,
            left: 20,
            child: _HudBox(
              child: Text(
                plateDetected
                    ? 'Prato detetado ✅'
                    : 'Prato não detetado (fallback) ⚠️',
                style: TextStyle(
                  color: plateDetected ? Colors.green : Colors.orange,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          Positioned(
            top: 130,
            left: 20,
            child: _HudBox(
              child: Text(
                'Deteções: $detectionsCount',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
          ),

          // Lista de top itens
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: _HudBox(
              child: top.isEmpty
                  ? const Text('Sem resultados ainda.',
                      style: TextStyle(color: Colors.white))
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: top.take(4).map((e) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  e.key,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${e.value.toStringAsFixed(0)} kcal',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HudBox extends StatelessWidget {
  final Widget child;
  const _HudBox({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}