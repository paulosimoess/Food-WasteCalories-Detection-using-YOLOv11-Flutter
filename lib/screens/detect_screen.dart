import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/ultralytics_yolo.dart';

import '../data/model_manager.dart';

class DetectScreen extends StatefulWidget {
  const DetectScreen({super.key});

  @override
  State<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends State<DetectScreen> {
  bool _isModelLoading = true;
  String? _modelPath;

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    setState(() => _isModelLoading = true);
    try {
      final path = await ModelManager.ensureModelPath();
      if (!mounted) return;
      setState(() {
        _modelPath = path;
        _isModelLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _modelPath = null;
        _isModelLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro a carregar modelo: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Deteção')),
      body: Stack(
        children: [
          if (!_isModelLoading && _modelPath != null)
            YOLOView(
              modelPath: _modelPath!,
              task: YOLOTask.detect, // live contínuo leve
              streamingConfig: const YOLOStreamingConfig.minimal(),
              onResult: (_) {
              },
            ),
          if (_isModelLoading) const Center(child: CircularProgressIndicator()),
          if (!_isModelLoading && _modelPath == null)
            const Center(child: Text('Falha a carregar o modelo.')),
        ],
      ),
    );
  }
}