import 'package:flutter/material.dart';
import 'package:ultralytics_yolo/yolo.dart';
import 'package:ultralytics_yolo/yolo_streaming_config.dart';
import 'package:ultralytics_yolo/yolo_view.dart';

void main() => runApp(App());

class App extends StatefulWidget {
  @override
  _AppState createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
  }


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: Text('Food waste detection')),
        body: Center(
          child: YOLOView(
            modelPath: 'model_N',
            task: YOLOTask.segment,
            useGpu: true,
            showNativeUI: false,
            streamingConfig: YOLOStreamingConfig(),
            onResult: (results) {
              results.forEach((obj) {
                print("Object ${obj.className}");
              });
            },
          ),
        ),
      ),
    );
  }
}