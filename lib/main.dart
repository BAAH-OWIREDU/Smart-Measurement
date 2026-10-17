import 'package:flutter/material.dart';
import 'screens/camera_viewfinder_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmartMeasurementsApp());
}

class SmartMeasurementsApp extends StatelessWidget {
  const SmartMeasurementsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Measurements',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const CameraViewfinderScreen(cameras: []),
    );
  }
}