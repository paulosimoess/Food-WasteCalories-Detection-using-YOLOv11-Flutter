// import 'dart:typed_data';

import 'package:flutter/material.dart';
// import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_task.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

void main() {
  runApp(MaterialApp(
    home: AdvancedCameraScreen(),
  ));
}

class AdvancedCameraScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: YOLOView(
        modelPath: 'model_N',
        task: YOLOTask.segment,

        // // Configure streaming behavior
        // streamingConfig: YOLOStreamingConfig.throttled(
        //   maxFPS: 15, // Limit to 15 FPS for battery saving
        //   includeMasks: false, // Disable masks for performance
        //   includeOriginalImage: false, // Save bandwidth
        // ),

        // Comprehensive callback
        // onStreamingData: (data) {
        //   final detections = data['detections'] as List? ?? [];
        //   final fps = data['fps'] as double? ?? 0.0;
        //   final originalImage = data['originalImage'] as Uint8List?;

        //   print('Streaming: ${detections.length} detections at ${fps.toStringAsFixed(1)} FPS');

        //   // Process complete frame data
        //   processFrameData(detections, originalImage);
        // },
      ),
    );
  }

  // void processFrameData(List detections, Uint8List? imageData) {
  //   // Custom processing logic
  //   for (final detection in detections) {
  //     final className = detection['className'] as String?;
  //     final confidence = detection['confidence'] as double?;

  //     if (confidence != null && confidence > 0.8) {
  //       print('High confidence detection: $className (${(confidence * 100).toStringAsFixed(1)}%)');
  //     }
  //   }
  // }
}