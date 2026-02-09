import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../data/model_manager.dart';
import '../data/calorie_service.dart';
import '../data/calorie_estimator.dart';

class DetectScreen extends StatefulWidget {
  const DetectScreen({super.key});

  @override
  State<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends State<DetectScreen> {
  bool _isModelLoading = true;
  String? _modelPath;

  final _calorieService = CalorieService();
  bool _assetsReady = false;

  // HUD state
  bool plateDetected = false;
  double wastePercentage = 0.0; // agora é "waste" mesmo (100 - food%)
  double _lastPlateArea = 0.0;

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

  // Config para garantir preview + deteções + máscaras (melhor para áreas)
  static const YOLOStreamingConfig _streamingConfig = YOLOStreamingConfig.custom(
    includeOriginalImage: true, // <<< evita ecrã “sem nada”
    includeDetections: true,
    includeMasks: true, // <<< para cálculo de área (se o modelo suportar)
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

    final detections = <Detection>[];
    double plateArea = 0.0;
    double garbageArea = 0.0;

    for (final object in data) {
      final x1 = object.boundingBox.left.toDouble();
      final y1 = object.boundingBox.top.toDouble();
      final x2 = object.boundingBox.right.toDouble();
      final y2 = object.boundingBox.bottom.toDouble();

      final bboxArea = (x2 - x1).abs() * (y2 - y1).abs();

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
    }

    final hasPlate = plateArea > 0;

    // “usable plate” (parte do prato sem garbage)
    final usablePlate = (plateArea - garbageArea).clamp(1.0, double.infinity);

    // foodArea: tudo exceto nonFood
    final foodArea = detections
        .where((d) => !CalorieEstimator.nonFood.contains(d.labelName))
        .fold<double>(0.0, (acc, d) => acc + d.area);

    // ✅ Agora waste = 100 - foodCoverage
    double newWaste = 0.0;
    if (hasPlate) {
      final foodCoverage = (foodArea / usablePlate) * 100.0;
      newWaste = (100.0 - foodCoverage).clamp(0.0, 100.0);
    }

    if (!mounted) return;
    setState(() {
      plateDetected = hasPlate;
      wastePercentage = newWaste;
      _lastPlateArea = plateArea;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Deteção de Desperdício Alimentar'),
      ),
      body: Stack(
        children: [
          if (!_isModelLoading && _modelPath != null)
            YOLOView(
              modelPath: _modelPath!,
              task: YOLOTask.segment, // melhor para áreas (waste)
              streamingConfig: _streamingConfig,
              onResult: (data) => _handleResult(data),
            ),

          if (_isModelLoading) const Center(child: CircularProgressIndicator()),
          if (!_isModelLoading && _modelPath == null)
            const Center(child: Text('Falha a carregar o modelo.')),

          // HUD (como tinhas antes)
          Positioned(
            top: 20,
            left: 20,
            child: _HudBox(
              child: Text(
                'Waste: ${wastePercentage.toStringAsFixed(2)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Positioned(
            top: 80,
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

          // (opcional) debug pequeno para veres se plateArea existe
          Positioned(
            top: 140,
            left: 20,
            child: _HudBox(
              child: Text(
                'plateArea: ${_lastPlateArea.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
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