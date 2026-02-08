import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import 'data/model_manager.dart';
import 'data/calorie_service.dart';
import 'data/calorie_estimator.dart';

void main() {
  runApp(const App());
}

enum AppMode { waste, calories }

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Food Waste Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0B0B0E),
              Color(0xFF050507),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const _LogoMark(),
                    const SizedBox(height: 14),
                    const Text(
                      'FreeFood Insight',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: Color(0xFFB91C1C),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Plataforma para deteção de desperdício alimentar e contagem de calorias.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 26),
                    Row(
                      children: [
                        Expanded(
                          child: _HomeCard(
                            title: 'Desperdício Alimentar',
                            subtitle:
                                'Aceder à aplicação base de deteção e cálculo de waste (%).',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CameraInferenceScreen(
                                    mode: AppMode.waste,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _HomeCard(
                            title: 'Contador de Calorias',
                            subtitle:
                                'Identificar alimento e estimar calorias.',
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const CameraInferenceScreen(
                                    mode: AppMode.calories,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      '© 2026 FreeFood Insight • Versão académica',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        color: const Color(0xFF121218),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
        boxShadow: const [
          BoxShadow(
            blurRadius: 18,
            offset: Offset(0, 10),
            color: Colors.black54,
          )
        ],
      ),
      child: const Center(
        child: Text(
          'S',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _HomeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _HomeCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F14),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Expanded(child: SizedBox()),
                Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white54),
              ],
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white60,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CameraInferenceScreen extends StatefulWidget {
  final AppMode mode;
  const CameraInferenceScreen({super.key, required this.mode});

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

  // =========================
  // PERF: throttle + smoothing
  // =========================
  DateTime _lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _uiIntervalMs = 250; // 4 updates/seg (ajusta: 150..400)

  // Calorias só a cada N updates (reduz MUITO lag)
  static const int _calorieEveryN = 3; // 2~1.3x/seg (depende do throttle)
  int _tick = 0;

  double _kcalSmoothed = 0.0; // suaviza total kcal (menos “saltos”)

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
      // retry 1x (às vezes assets/modelo falham 1ª vez)
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        await _calorieService.init();
        final path = await ModelManager.ensureModelPath();
        if (!mounted) return;
        setState(() {
          _assetsReady = true;
          _modelPath = path;
          _isModelLoading = false;
        });
        return;
      } catch (_) {}

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
      appBar: AppBar(
        title: Text(widget.mode == AppMode.calories
            ? 'Contador de Calorias'
            : 'Desperdício Alimentar'),
      ),
      body: Stack(
        children: [
          if (!_isModelLoading && _modelPath != null && _assetsReady)
            YOLOView(
              modelPath: _modelPath!,
              task: YOLOTask.segment,
              streamingConfig: const YOLOStreamingConfig.minimal(),
              onResult: (data) {
                // =========================
                // PERF: throttle UI updates
                // =========================
                final now = DateTime.now();
                if (now.difference(_lastUiUpdate).inMilliseconds < _uiIntervalMs) {
                  return;
                }
                _lastUiUpdate = now;

                _tick++;

                // Faz tudo em variáveis locais (sem setState aqui)
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
                final plateNow = plateArea > 0;
                double wasteNow = 0.0;

                if (plateArea > 0) {
                  final usablePlate =
                      (plateArea - garbageArea).clamp(1.0, double.infinity);

                  final foodArea = detections
                      .where((d) =>
                          !CalorieEstimator.nonFood.contains(d.labelName))
                      .fold<double>(0.0, (acc, d) => acc + d.area);

                  wasteNow = (foodArea / usablePlate) * 100.0;
                } else {
                  wasteNow = 0.0;
                }
                wasteNow = wasteNow.clamp(0.0, 100.0);

                // Calories (só se for modo calories, e só a cada N updates)
                double totalKcalNow = totalKcal;
                Map<String, double> kcalByLabelNow = kcalByLabel;

                if (widget.mode == AppMode.calories &&
                    plateArea > 0 &&
                    _assetsReady &&
                    (_tick % _calorieEveryN == 0)) {
                  final res = CalorieEstimator.estimate(
                    objects: detections,
                    plateArea: plateArea,
                    garbageArea: garbageArea,
                    gramsPerPlateFallback: 500.0,
                    kcalBase: _calorieService.kcalPer100g,
                  );

                  totalKcalNow = res.total;

                  final tmp = <String, double>{};
                  for (final it in res.items) {
                    tmp[it.labelName] =
                        (tmp[it.labelName] ?? 0.0) + it.kcalEstimated;
                  }
                  kcalByLabelNow = tmp;

                  // smoothing (só quando recalcula)
                  _kcalSmoothed = (_kcalSmoothed == 0.0)
                      ? totalKcalNow
                      : (_kcalSmoothed * 0.7 + totalKcalNow * 0.3);
                  totalKcalNow = _kcalSmoothed;
                }

                if (!mounted) return;
                setState(() {
                  plateDetected = plateNow;
                  wastePercentage = wasteNow;

                  // só mexe nas calorias quando for modo calories
                  if (widget.mode == AppMode.calories) {
                    totalKcal = totalKcalNow;
                    kcalByLabel = kcalByLabelNow;
                  } else {
                    totalKcal = 0.0;
                    kcalByLabel = {};
                    _kcalSmoothed = 0.0;
                  }
                });
              },
            ),

          if (_isModelLoading) const Center(child: CircularProgressIndicator()),
          if (!_isModelLoading && _modelPath == null)
            const Center(child: Text('Falha a carregar o modelo.')),

          Positioned(
            top: 14,
            left: 14,
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
            top: 74,
            left: 14,
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

          if (widget.mode == AppMode.calories) ...[
            Positioned(
              top: 134,
              left: 14,
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
              top: 184,
              left: 14,
              child: _HudBox(
                child: Text(
                  topText.isEmpty ? 'Sem kcal' : topText,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ],
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