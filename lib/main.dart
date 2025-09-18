import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

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
  bool _isModelLoading = false;

  @override
  void initState() {
    super.initState();

    _loadModelForPlatform();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          if (!_isModelLoading)
            YOLOView(
              modelPath: 'model_N',
              task: YOLOTask.segment,
              streamingConfig: const YOLOStreamingConfig.minimal(),
              onResult: (data) {
                const foodWasteClassName = 'placeholder';

                final detectionsWithArea = data.map((d) {
                  final rect = d.boundingBox;
                  final area =
                      (rect.right - rect.left) * (rect.bottom - rect.top);
                  return {'className': d.className, 'area': area};
                }).toList();

                final foodWasteDetections = detectionsWithArea
                    .where((d) => d['className'] == foodWasteClassName)
                    .toList();

                final totalWasteCount = foodWasteDetections.length;
                final totalWasteArea = foodWasteDetections.fold<double>(
                  0,
                  (sum, d) => sum + (d['area'] as double? ?? 0),
                );
                final totalDetections = detectionsWithArea.length;
                final wastePercentage = totalDetections > 0
                    ? (totalWasteCount / totalDetections * 100)
                    : 0;

                debugPrint('Food Waste Count: $totalWasteCount');
                debugPrint('Food Waste Area: $totalWasteArea');
                debugPrint(
                  'Waste Percentage: ${wastePercentage.toStringAsFixed(2)}%',
                );
              },
            ),
        ],
      ),
    );
  }

  // assyncronous model loading -- A fix for the onResult
  Future<void> _loadModelForPlatform() async {
    setState(() {
      _isModelLoading = true;
    });

    await Future.delayed(const Duration(seconds: 6));

    if (mounted) {
      setState(() {
        _isModelLoading = false;
      });
    }
  }
}
