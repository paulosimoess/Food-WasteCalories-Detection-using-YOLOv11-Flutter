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
  bool plateDetected = false;
  double wastePercentage = 0;

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
              modelPath: 'model_M',
              task: YOLOTask.segment,
              streamingConfig: const YOLOStreamingConfig.minimal(),
              onResult: (data) {
                setState(() {
                  List<int> ignoreClasses = [
                    8, // board
                    11, // bread
                    22, // chips
                    25, // coffee cup
                    27, // cup
                    31, // fork
                    42, // knife
                    58, // plate
                    70, // spoon
                    83, // water cup
                  ];

                  List<int> garbageClasses = [
                    35, // general garbage
                  ];

                  // areas
                  double plateArea = 0;
                  double foodArea = 0;
                  double garbageArea = 0;

                  // area sum
                  // the area for bounding boxes can be calculated with (x_max - x_min) * (y_max - y_min)
                  for (var object in data) {
                    // plateArea -- class number 58
                    if (object.classIndex == 58) {
                      plateArea +=
                          (object.boundingBox.right - object.boundingBox.left) *
                          (object.boundingBox.bottom - object.boundingBox.top);

                      plateDetected = true;
                    }

                    // garbage area
                    if (garbageClasses.contains(object.classIndex)) {
                      garbageArea +=
                          (object.boundingBox.right - object.boundingBox.left) *
                          (object.boundingBox.bottom - object.boundingBox.top);
                    }

                    // food area
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

                  // fix values between 0 and 100 -- fixing possible overflows
                  wastePercentage = wastePercentage.clamp(0, 100);
                });
              },
            ),
          if (_isModelLoading) const Center(child: CircularProgressIndicator()),
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
