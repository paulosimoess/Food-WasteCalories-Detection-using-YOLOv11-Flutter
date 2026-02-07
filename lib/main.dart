import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';
import 'data/model_manager.dart';

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

  bool plateDetected = false;
  double wastePercentage = 0;

  @override
  void initState() {
    super.initState();
    _prepareModel();
  }

  Future<void> _prepareModel() async {
    setState(() => _isModelLoading = true);

    try {
      final path = await ModelManager.ensureModelPath();
      if (!mounted) return;

      setState(() {
        _modelPath = path;     // <-- caminho completo do ficheiro no telemóvel
        _isModelLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelPath = null;
        _isModelLoading = false;
      });
      // Opcional: mostra erro
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro a preparar modelo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (!_isModelLoading && _modelPath != null)
            YOLOView(
              modelPath: _modelPath!, // <-- em vez de 'model_M'
              task: YOLOTask.segment,
              streamingConfig: const YOLOStreamingConfig.minimal(),
              onResult: (data) {
                setState(() {
                  List<int> ignoreClasses = [
                    8, 11, 22, 25, 27, 31, 42, 58, 70, 83
                  ];

                  List<int> garbageClasses = [35];

                  double plateArea = 0;
                  double foodArea = 0;
                  double garbageArea = 0;

                  for (var object in data) {
                    if (object.classIndex == 58) {
                      plateArea +=
                          (object.boundingBox.right - object.boundingBox.left) *
                          (object.boundingBox.bottom - object.boundingBox.top);
                      plateDetected = true;
                    }

                    if (garbageClasses.contains(object.classIndex)) {
                      garbageArea +=
                          (object.boundingBox.right - object.boundingBox.left) *
                          (object.boundingBox.bottom - object.boundingBox.top);
                    }

                    if (!ignoreClasses.contains(object.classIndex) &&
                        !garbageClasses.contains(object.classIndex)) {
                      foodArea +=
                          (object.boundingBox.right - object.boundingBox.left) *
                          (object.boundingBox.bottom - object.boundingBox.top);
                    }
                  }

                  if (plateArea > 0) {
                    wastePercentage =
                        (foodArea / (plateArea - garbageArea)) * 100;
                  } else {
                    wastePercentage = 0;
                    plateDetected = false;
                  }

                  wastePercentage = wastePercentage.clamp(0, 100);
                });
              },
            ),

          if (_isModelLoading)
            const Center(child: CircularProgressIndicator()),

          if (!_isModelLoading && _modelPath == null)
            const Center(child: Text('Falha a carregar o modelo.')),

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
        ],
      ),
    );
  }
}