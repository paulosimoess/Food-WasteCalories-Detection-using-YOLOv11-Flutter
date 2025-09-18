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
                if (kDebugMode) {
                  String _className = data.isNotEmpty
                      ? data[0].className
                      : 'No class';
                  print('Class Name: $_className');
                }
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
