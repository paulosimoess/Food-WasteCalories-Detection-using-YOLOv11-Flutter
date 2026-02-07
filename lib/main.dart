import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'data/model_manager.dart';
import 'data/calorie_service.dart';
import 'data/calorie_estimator.dart';

void main() {
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Food Waste Detection',
      home: CameraInferenceScreen(),
    );
  }
}

class CameraInferenceScreen extends StatefulWidget {
  const CameraInferenceScreen({super.key});

  @override
  State<CameraInferenceScreen> createState() => _CameraInferenceScreenState();
}

class _CameraInferenceScreenState extends State<CameraInferenceScreen> {
  bool _isModelLoading = true;
  String? _modelPath;

  // Waste UI
  bool plateDetected = false;
  double wastePercentage = 0.0;

  // Calories
  final _calorieService = CalorieService();
  bool _assetsReady = false;

  double totalKcal = 0.0;
  Map<String, double> kcalByLabel = {};

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    setState(() => _isModelLoading = true);

    try {
      // carregar labels + calorie map (assets/)
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

  @override
  Widget build(BuildContext context) {
    final top3 = kcalByLabel.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final topText = top3
        .take(3)
        .map((e) => '${e.key}: ${e.value.toStringAsFixed(0)}')
        .join('\n');

    return Scaffold(
      body: Stack(
        children: [
          if (!_isModelLoading && _modelPath != null)
            YOLOView(
              modelPath: _modelPath!,
              task: YOLOTask.segment,
              streamingConfig: const YOLOStreamingConfig.minimal(),
              onResult: (data) {
                setState(() {
                  // Converter results -> detections 
                  final detections = <Detection>[];

                  double plateArea = 0.0;
                  double garbageArea = 0.0;

                  for (final object in data) {
                    final x1 = object.boundingBox.left.toDouble();
                    final y1 = object.boundingBox.top.toDouble();
                    final x2 = object.boundingBox.right.toDouble();
                    final y2 = object.boundingBox.bottom.toDouble();

                    final bboxArea = (x2 - x1).abs() * (y2 - y1).abs();

                    final label =
                        _calorieService.labelForIndex(object.classIndex);
                    final labelNorm = label.trim().toLowerCase();

                    // confidence: tenta ler do object; se não existir no plugin, fica 1.0
                    double conf = 1.0;
                    try {
                      final dynamic anyObj = object;
                      final dynamic c =
                          anyObj.confidence ?? anyObj.conf ?? anyObj.score;
                      if (c is num) conf = c.toDouble();
                    } catch (_) {
                      conf = 1.0;
                    }

                    // area: tenta usar mask area (se existir); senão bbox area
                    double usedArea = bboxArea;
                    try {
                      final dynamic anyObj = object;
                      final dynamic m = anyObj.maskArea ??
                          anyObj.segmentationArea ??
                          anyObj.mask_area;
                      if (m is num && m.toDouble() > 0) {
                        usedArea = m.toDouble();
                      }
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
                  }

                  // Waste %
                  plateDetected = plateArea > 0;

                  if (plateArea > 0) {
                    final usablePlate =
                        (plateArea - garbageArea).clamp(1.0, double.infinity);

                    final foodArea = detections
                        .where((d) =>
                            !CalorieEstimator.nonFood.contains(d.labelName))
                        .fold<double>(0.0, (acc, d) => acc + d.area);

                    wastePercentage = (foodArea / usablePlate) * 100.0;
                  } else {
                    wastePercentage = 0.0;
                  }

                  wastePercentage = wastePercentage.clamp(0.0, 100.0);

                  // Calories 
                  totalKcal = 0.0;
                  kcalByLabel = {};

                  if (plateArea > 0 && _assetsReady) {
                    final res = CalorieEstimator.estimate(
                      objects: detections,
                      plateArea: plateArea,
                      garbageArea: garbageArea,
                      gramsPerPlateFallback: 500.0,
                      kcalBase: _calorieService.kcalPer100g,
                    );

                    totalKcal = res.total;

                    for (final it in res.items) {
                      kcalByLabel[it.labelName] =
                          (kcalByLabel[it.labelName] ?? 0.0) +
                              it.kcalEstimated;
                    }
                  }
                });
              },
            ),

          if (_isModelLoading) const Center(child: CircularProgressIndicator()),
          if (!_isModelLoading && _modelPath == null)
            const Center(child: Text('Falha a carregar o modelo.')),

          Positioned(
            top: 50,
            left: 20,
            child: _HudBox(
              child: Text(
                'Waste (CAL v1): ${wastePercentage.toStringAsFixed(2)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Positioned(
            top: 110,
            left: 20,
            child: _HudBox(
              child: Text(
                'Plate detected: $plateDetected',
                style: TextStyle(
                  color: plateDetected ? Colors.green : Colors.red,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Positioned(
            top: 170,
            left: 20,
            child: _HudBox(
              child: Text(
                'Kcal: ${totalKcal.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          Positioned(
            top: 220,
            left: 20,
            child: _HudBox(
              child: Text(
                topText.isEmpty ? 'Sem kcal' : topText,
                style: const TextStyle(color: Colors.white, fontSize: 14),
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
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}