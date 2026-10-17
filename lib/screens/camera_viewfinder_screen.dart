import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Conditional imports to prevent VM test crashes
import 'camera_viewfinder_stub.dart'
    if (dart.library.html) 'camera_viewfinder_web.dart';

class CameraViewfinderScreen extends StatelessWidget {
  final List<dynamic> cameras;

  const CameraViewfinderScreen({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: CameraViewfinderBody(),
    );
  }
}