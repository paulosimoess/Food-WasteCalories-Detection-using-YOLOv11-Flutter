import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
// import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:tensorflow_lite_flutter/tensorflow_lite_flutter.dart';
import 'package:image/image.dart' as img;
import 'dart:typed_data';

late List<CameraDescription> cameras;

class RealTimeSegmentation extends StatefulWidget {
  const RealTimeSegmentation({super.key});

  @override
  State<RealTimeSegmentation> createState() => _RealTimeSegmentationState();
}

class _RealTimeSegmentationState extends State<RealTimeSegmentation> {
  late CameraController cameraController;
  
  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    cameras = await availableCameras();
    cameraController = CameraController(cameras[0], ResolutionPreset.low);
    
    await cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      startCamera();
      loadModel();
    });
  }

  void startCamera() {
    cameraController.startImageStream((CameraImage image) {
      // with the result of the image pre-process here
    });
  }

  // taken from https://pub.dev/documentation/tensorflow_lite_flutter/latest/#setup
  Future<void> loadModel() async {
    try {
      String? result = await Tflite.loadModel(
        model: "assets/model.tflite",
        labels: "assets/labels.txt",
        numThreads: 2,         // Number of threads to use (default: 1)
        isAsset: true,         // Is the model file an asset or a file? (default: true)
        useGpuDelegate: false  // Use GPU acceleration? (default: false)
      );
      print('Model loaded successfully: $result');
    } catch (e) {
      print('Failed to load model: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!cameraController.value.isInitialized) {
      return Container();
    }

    return Scaffold(
      body: Stack(
        children: <Widget>[
          CameraPreview(cameraController),
        ],
      ),
    );
  }

  @override
  void dispose() {
    cameraController.dispose();
    super.dispose();
  }
}