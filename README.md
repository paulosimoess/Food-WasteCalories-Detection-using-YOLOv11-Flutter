# Food WasteDetection using YOLOv11 (Flutter)

This is an adapted version of [Food Waste Detection using YOLOv11](https://github.com/Xurape/Food-Waste-Detection-using-YOLOv11)

## Important package fixes

Change cached package `pub.dev\tensorflow_lite_flutter-3.0.0\android\src\main\AndroidManifest.xml`
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
  package="sq.flutter.tflite">
</manifest>
```
to
```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
</manifest>
```

