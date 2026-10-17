import 'dart:js' as js;
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

class MediaPipeService {
  dynamic _poseInstance;
  bool _isInitialized = false;

  /// Initialize MediaPipe Pose model configuration
  Future<void> initialize(Function(dynamic results) onResults) async {
    try {
      // Check if global window.Pose is available from CDN
      if (js.context['Pose'] == null) {
        throw 'MediaPipe Pose script not loaded in index.html';
      }

      // Instantiate window.Pose object
      _poseInstance = js.context['Pose'].callMethod('new', [
        js.JsObject.jsify({
          'locateFile': (String file, String basePath) {
            return 'https://cdn.jsdelivr.com/npm/@mediapipe/pose/$file';
          }
        })
      ]);

      // Set options for pose detection accuracy
      _poseInstance.callMethod('setOptions', [
        js.JsObject.jsify({
          'modelComplexity': 1,
          'smoothLandmarks': true,
          'enableSegmentation': false,
          'minDetectionConfidence': 0.5,
          'minTrackingConfidence': 0.5,
        })
      ]);

      // Register results callback listener
      _poseInstance.callMethod('onResults', [
        (js.JsObject results) {
          onResults(results);
        }
      ]);

      _isInitialized = true;
      debugPrint('MediaPipe Pose initialized successfully.');
    } catch (e) {
      debugPrint('Error initializing MediaPipe Pose: $e');
    }
  }

  /// Send a video frame to MediaPipe for inference
  Future<void> sendFrame(html.VideoElement videoElement) async {
    if (!_isInitialized || _poseInstance == null) return;
    try {
      await _poseInstance.callMethod('send', [
        js.JsObject.jsify({'image': videoElement})
      ]);
    } catch (e) {
      // Frame drop or send error handling during active stream
    }
  }

  void dispose() {
    if (_poseInstance != null) {
      _poseInstance.callMethod('close');
      _isInitialized = false;
    }
  }
}