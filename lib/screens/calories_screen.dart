import 'dart:async';

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

  // Assets
  final _calorieService = CalorieService();
  bool _assetsReady = false;

  // UI state
  bool plateDetected = false;
  double wastePercentage = 0.0;
  double totalKcal = 0.0;
  Map<String, double> kcalByLabel = {};

  // Mode control
  YOLOTask _task = YOLOTask.detect; // LIVE leve
  Key _yoloKey = UniqueKey();

  bool _detecting = false; // botão "Detectar" ativo
  bool _busy = false;
  DateTime _lastProcessed = DateTime.fromMillisecondsSinceEpoch(0);
  final Duration _processEvery = const Duration(milliseconds: 450); // throttle

  Timer? _detectTimeout;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  @override
  void dispose() {
    _detectTimeout?.cancel();
    super.dispose();
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

  YOLOStreamingConfig get _streamingConfig {
    // LIVE (detect) -> preview sempre, leve, sem máscaras
    if (_task == YOLOTask.detect && !_detecting) {
      return const YOLOStreamingConfig.custom(
        includeOriginalImage: true, // <<< evita ecrã preto
        includeDetections: true,
        includeMasks: false,
        includeFps: false,
        includeProcessingTimeMs: false,
        includeClassifications: false,
        includePoses: false,
        includeOBB: false,
        maxFPS: 15,
        inferenceFrequency: 8,
        throttleInterval: Duration(milliseconds: 200),
      );
    }

    // SEGMENT (Detectar) -> máscaras para área
    return const YOLOStreamingConfig.custom(
      includeOriginalImage: true, // <<< mantém preview
      includeDetections: true,
      includeMasks: true,
      includeFps: false,
      includeProcessingTimeMs: false,
      includeClassifications: false,
      includePoses: false,
      includeOBB: false,
      maxFPS: 10,
      inferenceFrequency: 6,
      throttleInterval: Duration(milliseconds: 250),
    );
  }

  void _switchTask(YOLOTask newTask) {
    if (_task == newTask) return;
    setState(() {
      _task = newTask;
      _yoloKey = UniqueKey(); // força reinicialização do YOLOView
    });
  }

  void _startDetectOnce() {
    if (!_assetsReady || _modelPath == null) return;

    setState(() => _detecting = true);
    _switchTask(YOLOTask.segment);

    // se por algum motivo não vier resultado, volta ao live após timeout
    _detectTimeout?.cancel();
    _detectTimeout = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      if (_detecting) {
        setState(() => _detecting = false);
        _switchTask(YOLOTask.detect);
      }
    });
  }

  void _stopDetectMode() {
    _detectTimeout?.cancel();
    if (!mounted) return;
    setState(() => _detecting = false);
    _switchTask(YOLOTask.detect);
  }

  void _handleResult(List<dynamic> data) {
    final now = DateTime.now();
    if (_busy) return;
    if (now.difference(_lastProcessed) < _processEvery) return;
    _lastProcessed = now;

    final shouldCompute = _detecting || _task == YOLOTask.segment;
    if (!shouldCompute) return;

    _busy = true;

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

    final bool newPlateDetected = plateArea > 0;
    double newWaste = 0.0;

    if (plateArea > 0) {
      final usablePlate = (plateArea - garbageArea).clamp(1.0, double.infinity);
      final foodArea = detections
          .where((d) => !CalorieEstimator.nonFood.contains(d.labelName))
          .fold<double>(0.0, (acc, d) => acc + d.area);
      newWaste = (foodArea / usablePlate) * 100.0;
    }
    newWaste = newWaste.clamp(0.0, 100.0);

    double newTotalKcal = 0.0;
    final newKcalByLabel = <String, double>{};

    if (plateArea > 0 && _assetsReady) {
      final res = CalorieEstimator.estimate(
        objects: detections,
        plateArea: plateArea,
        garbageArea: garbageArea,
        gramsPerPlateFallback: 500.0,
        kcalBase: _calorieService.kcalPer100g,
      );

      newTotalKcal = res.total;

      for (final it in res.items) {
        newKcalByLabel[it.labelName] =
            (newKcalByLabel[it.labelName] ?? 0.0) + it.kcalEstimated;
      }
    }

    if (mounted) {
      setState(() {
        plateDetected = newPlateDetected;
        wastePercentage = newWaste;
        totalKcal = newTotalKcal;
        kcalByLabel = newKcalByLabel;
      });
    }

    // Se estava em modo detectar, fecha logo após 1 resultado
    if (_detecting) {
      _stopDetectMode();
    }

    _busy = false;
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
      appBar: AppBar(
        title: const Text('Calorias'),
      ),
      body: Stack(
        children: [
          if (!_isModelLoading && _modelPath != null)
            YOLOView(
              key: _yoloKey,
              modelPath: _modelPath!,
              task: _task,
              streamingConfig: _streamingConfig,
              onResult: (data) => _handleResult(data),
            ),

          if (_isModelLoading) const Center(child: CircularProgressIndicator()),
          if (!_isModelLoading && _modelPath == null)
            const Center(child: Text('Falha a carregar o modelo.')),

          Positioned(
            top: 20,
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

          Positioned(
            top: 140,
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
            top: 190,
            left: 20,
            child: _HudBox(
              child: Text(
                topText.isEmpty ? 'Sem kcal' : topText,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
          ),

          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: (_assetsReady && !_detecting) ? _startDetectOnce : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: Text(_detecting ? 'A detectar…' : 'Detectar'),
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