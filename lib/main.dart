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
  double wastePercentage = 0;

  // Calories
  final _calorieService = CalorieService();
  final _estimator = CalorieEstimator();
  bool _assetsReady = false;

  double totalKcal = 0;
  Map<String, double> kcalByLabel = {};

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    setState(() => _isModelLoading = true);

    try {
      // 1) carregar labels + calorie map (assets/)
      await _calorieService.init();

      // 2) garantir modelo (zip -> documents -> path)
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
    // Top 3 (para não encher o ecrã)
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
              modelPath: _modelPath!, // caminho completo no telemóvel
              task: YOLOTask.segment,
              streamingConfig: const YOLOStreamingConfig.minimal(),
              onResult: (data) {
                setState(() {
                  // Índices conforme o teu labels.txt
                  List<int> ignoreClasses = [
                    8, 11, 22, 25, 27, 31, 42, 58, 70, 83
                  ];
                  List<int> garbageClasses = [35];

                  double plateArea = 0;
                  double garbageArea = 0;

                  // áreas de comida por classe (para kcal)
                  final Map<int, double> areaByClass = {};

                  for (var object in data) {
                    final area =
                        (object.boundingBox.right - object.boundingBox.left) *
                        (object.boundingBox.bottom - object.boundingBox.top);

                    if (object.classIndex == 58) {
                      plateArea += area;
                      plateDetected = true;
                      continue;
                    }

                    if (garbageClasses.contains(object.classIndex)) {
                      garbageArea += area;
                      continue;
                    }

                    if (!ignoreClasses.contains(object.classIndex)) {
                      areaByClass[object.classIndex] =
                          (areaByClass[object.classIndex] ?? 0) + area;
                    }
                  }

                  // Waste %
                  if (plateArea > 0) {
                    final usablePlate =
                        (plateArea - garbageArea).clamp(1.0, double.infinity);
                    final foodArea =
                        areaByClass.values.fold(0.0, (a, b) => a + b);

                    wastePercentage = (foodArea / usablePlate) * 100;
                  } else {
                    wastePercentage = 0;
                    plateDetected = false;
                  }

                  wastePercentage = wastePercentage.clamp(0, 100);

                  // Calories
                  totalKcal = 0;
                  kcalByLabel = {};

                  if (plateArea > 0 && _assetsReady) {
                    final usablePlate =
                        (plateArea - garbageArea).clamp(1.0, double.infinity);

                    areaByClass.forEach((classIdx, classArea) {
                      // porção estimada pela área do prato útil
                      double portion = classArea / usablePlate;
                      portion =
                          portion.clamp(0.0, _estimator.maxPortionPerItem);

                      final grams = _estimator.gramsFromPortion(portion);
                      if (grams < _estimator.minGramsItem) return;

                      final label = _calorieService.labelForIndex(classIdx);
                      final kcal100 = _calorieService.kcal100gForIndex(classIdx);
                      if (kcal100 <= 0) return;

                      final kcal = _estimator.kcalFromGrams(
                        grams: grams,
                        kcalPer100g: kcal100,
                      );

                      totalKcal += kcal;
                      kcalByLabel[label] = (kcalByLabel[label] ?? 0) + kcal;
                    });
                  }
                });
              },
            ),

          if (_isModelLoading) const Center(child: CircularProgressIndicator()),

          if (!_isModelLoading && _modelPath == null)
            const Center(child: Text('Falha a carregar o modelo.')),

          // Waste %
          Positioned(
            top: 50,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
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

          // Plate detected
          Positioned(
            top: 110,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Plate detected: ${plateDetected.toString()}',
                style: TextStyle(
                  color: plateDetected ? Colors.green : Colors.red,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Total kcal
          Positioned(
            top: 170,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
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

          // Top 3 itens
          Positioned(
            top: 220,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(10),
              ),
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