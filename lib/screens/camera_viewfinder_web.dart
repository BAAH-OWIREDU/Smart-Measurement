import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/mediapipe_service.dart';
import '../services/measurement_service.dart';

class CameraViewfinderBody extends StatefulWidget {
  const CameraViewfinderBody({super.key});

  @override
  State<CameraViewfinderBody> createState() => _CameraViewfinderBodyState();
}

class _CameraViewfinderBodyState extends State<CameraViewfinderBody>
    with SingleTickerProviderStateMixin {
  html.VideoElement? _videoElement;
  bool _isStreaming = false;
  String? _errorMessage;
  final String _viewId = 'smart-measurement-webcam';

  late final MediaPipeService _mediaPipeService;
  List<dynamic>? _latestLandmarks;
  bool _isProcessingFrames = false;

  bool _isAligned = false; // Controls Red/Green HUD box state
  Map<String, dynamic>? _capturedMeasurements;
  bool _isMeasuring = false;
  bool _copiedToClipboard = false;
  bool _useMetricUnit = false;

  // --- AUTO-GUIDANCE & 2-STEP WIZARD STATE ---
  int _scanStep = 1; // 1: Front View, 2: Side Profile View
  Map<String, dynamic> _frontScanData = {};
  String _guidanceInstruction = "Position yourself in camera view";
  String _heightDisplay = "Waiting...";
  String _shoulderDisplay = "Waiting...";

  int _frameCount = 0;
  int _fps = 0;
  Timer? _fpsTimer;

  late AnimationController _scanAnimationController;
  final TextEditingController _heightController =
      TextEditingController(text: '68'); // Default height baseline in inches

  @override
  void initState() {
    super.initState();
    _mediaPipeService = MediaPipeService();

    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _videoElement = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    ui_web.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      return _videoElement!;
    });

    _mediaPipeService.initialize((results) {
      if (mounted) {
        final landmarks = results['poseLandmarks'];
        _frameCount++;
        setState(() {
          _latestLandmarks = landmarks;
        });

        if (landmarks != null && landmarks is List && landmarks.length > 12) {
          _evaluateAutoGuidance(landmarks);
        } else {
          setState(() {
            _isAligned = false;
            _guidanceInstruction = "No human detected. Step into frame.";
          });
        }
      }
    });

    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _fps = _frameCount;
          _frameCount = 0;
        });
      }
    });
  }

  // --- REAL-TIME LIVENESS & POSITION EVALUATION ---
  void _evaluateAutoGuidance(List<dynamic> landmarks) {
    try {
      final nose = landmarks[0];
      final leftShoulder = landmarks[11];
      final rightShoulder = landmarks[12];

      if (nose == null || leftShoulder == null || rightShoulder == null) return;

      double noseX = (nose['x'] ?? 0.5);
      double shoulderWidth = sqrt(
        pow(((rightShoulder['x'] ?? 0) - (leftShoulder['x'] ?? 0)), 2) + 
        pow(((rightShoulder['y'] ?? 0) - (leftShoulder['y'] ?? 0)), 2)
      );

      // 1. Horizontal Centering Check
      if (noseX < 0.35) {
        setState(() {
          _isAligned = false;
          _guidanceInstruction = "STEP SLIGHTLY RIGHT ➔";
        });
        return;
      }
      if (noseX > 0.65) {
        setState(() {
          _isAligned = false;
          _guidanceInstruction = "⬅ STEP SLIGHTLY LEFT";
        });
        return;
      }

      // 2. Distance/Framing Check
      if (shoulderWidth < 0.15) {
        setState(() {
          _isAligned = false;
          _guidanceInstruction = "STEP CLOSER TO CAMERA ⬆";
        });
        return;
      }
      if (shoulderWidth > 0.60) {
        setState(() {
          _isAligned = false;
          _guidanceInstruction = "STEP BACK SLIGHTLY ⬇";
        });
        return;
      }

      // 3. PERFECT POSITION REACHED (Box turns Green)
      if (!_isAligned && !_isMeasuring) {
        setState(() {
          _isAligned = true;
          _guidanceInstruction = _scanStep == 1 
              ? "PERFECT! HOLD FOR FRONT SCAN" 
              : "PERFECT! HOLD FOR PROFILE SCAN";
        });

        // Update live metrics preview while aligned
        double knownHeight = double.tryParse(_heightController.text) ?? 68.0;
        double estimatedHeightPx = shoulderWidth * 3.45; 
        if (estimatedHeightPx > 0) {
          double ratio = knownHeight / estimatedHeightPx;
          double liveShoulder = shoulderWidth * ratio * 1.15 * 10;
          final unitLabel = _useMetricUnit ? 'cm' : 'in';
          
          setState(() {
            _heightDisplay = "${_useMetricUnit ? (knownHeight * 2.54).toStringAsFixed(1) : knownHeight} $unitLabel";
            _shoulderDisplay = "${_useMetricUnit ? (liveShoulder * 2.54).toStringAsFixed(1) : liveShoulder.toStringAsFixed(1)} $unitLabel";
          });
        }

        // Automatically trigger snapshot capture after 1 second of holding position
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted && _isAligned && !_isMeasuring && _capturedMeasurements == null) {
            _triggerAutomatedCapture(landmarks);
          }
        });
      }
    } catch (_) {}
  }

  // --- AUTOMATED CAPTURE LOGIC ---
  void _triggerAutomatedCapture(List<dynamic> landmarks) async {
    setState(() => _isMeasuring = true);

    await Future.delayed(const Duration(milliseconds: 300));
    double knownHeight = double.tryParse(_heightController.text) ?? 68.0;

    final leftShoulder = landmarks[11];
    final rightShoulder = landmarks[12];

    double shoulderPx = sqrt(
      pow(((rightShoulder['x'] ?? 0) - (leftShoulder['x'] ?? 0)), 2) + 
      pow(((rightShoulder['y'] ?? 0) - (leftShoulder['y'] ?? 0)), 2)
    );

    double estimatedHeightPx = shoulderPx * 3.45;
    double scaleRatio = knownHeight / estimatedHeightPx;
    double calculatedShoulder = shoulderPx * scaleRatio * 1.15;

    if (_scanStep == 1) {
      // Save Step 1 (Front View) and advance to Step 2 (Profile View)
      _frontScanData = {
        'shoulderWidth': calculatedShoulder,
        'torsoLength': estimatedHeightPx * scaleRatio * 0.38,
      };

      setState(() {
        _scanStep = 2;
        _isMeasuring = false;
        _isAligned = false;
        _guidanceInstruction = "STEP 2: TURN SIDEWAYS (PROFILE)";
      });
    } else {
      // Step 2 Complete: Finalize Report
      double finalShoulder = (_frontScanData['shoulderWidth'] + calculatedShoulder) / 2;
      double finalTorso = _frontScanData['torsoLength'];

      String size = 'M';
      String desc = 'Standard tailored fit';
      if (finalShoulder > 19.0) {
        size = 'XL';
        desc = 'Extended frame tailored fit';
      } else if (finalShoulder > 17.5) {
        size = 'L';
        desc = 'Large athletic fit';
      } else if (finalShoulder < 15.0) {
        size = 'S';
        desc = 'Slim fitted profile';
      }

      setState(() {
        _capturedMeasurements = {
          'shoulderWidth': finalShoulder,
          'torsoLength': finalTorso,
          'estimatedHeight': knownHeight,
          'recommendedSize': size,
          'fitDescription': desc,
        };
        _isMeasuring = false;
        _scanStep = 1;
      });
    }
  }

  Future<void> _startCameraStream() async {
    setState(() => _errorMessage = null);

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) throw 'Camera API not supported.';

      final mediaStream = await mediaDevices.getUserMedia({
        'video': {'facingMode': {'ideal': 'environment'}},
        'audio': false,
      });

      if (mediaStream != null && _videoElement != null) {
        _videoElement!.srcObject = mediaStream;
        await _videoElement!.play();
        if (mounted) {
          setState(() => _isStreaming = true);
          _startPoseInferenceLoop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Camera permission denied or device not found.');
      }
    }
  }

  void _startPoseInferenceLoop() {
    _isProcessingFrames = true;
    void loop() async {
      if (!_isProcessingFrames || !_isStreaming) return;
      if (_videoElement != null && _videoElement!.readyState >= 2) {
        await _mediaPipeService.sendFrame(_videoElement!);
      }
      html.window.requestAnimationFrame((_) => loop());
    }

    html.window.requestAnimationFrame((_) => loop());
  }

  void _copyMeasurementsToClipboard() {
    if (_capturedMeasurements == null) return;
    final unitLabel = _useMetricUnit ? 'cm' : '"';
    final shoulder = _convertUnit((_capturedMeasurements!['shoulderWidth'] as num).toDouble());
    final torso = _convertUnit((_capturedMeasurements!['torsoLength'] as num).toDouble());
    final height = _convertUnit((_capturedMeasurements!['estimatedHeight'] as num).toDouble());
    final size = _capturedMeasurements!['recommendedSize'];
    final desc = _capturedMeasurements!['fitDescription'];

    final summary = 'Smart Measurements AI Report:\n'
        '• Recommended Apparel Size: Size $size ($desc)\n'
        '• Shoulder Width: $shoulder $unitLabel\n'
        '• Torso Length: $torso $unitLabel\n'
        '• Height Reference: $height $unitLabel';

    html.window.navigator.clipboard?.writeText(summary);
    setState(() => _copiedToClipboard = true);
  }

  double _convertUnit(double valInInches) {
    if (_useMetricUnit) {
      return double.parse((valInInches * 2.54).toStringAsFixed(1));
    }
    return valInInches;
  }

  @override
  void dispose() {
    _isProcessingFrames = false;
    _fpsTimer?.cancel();
    _scanAnimationController.dispose();
    _mediaPipeService.dispose();
    _heightController.dispose();
    if (_videoElement?.srcObject != null) {
      final stream = _videoElement?.srcObject as html.MediaStream?;
      stream?.getTracks().forEach((track) => track.stop());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unitLabel = _useMetricUnit ? 'cm' : 'in';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isStreaming)
            HtmlElementView(viewType: _viewId)
          else
            Container(
              color: Colors.black,
              child: Center(
                child: _errorMessage != null
                    ? Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.white70, fontSize: 16),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),

          if (_isStreaming)
            AnimatedBuilder(
              animation: _scanAnimationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: MonochromePoseHUDPainter(
                    landmarks: _latestLandmarks,
                    isAligned: _isAligned,
                    scanProgress: _scanAnimationController.value,
                    isMeasuring: _isMeasuring,
                  ),
                );
              },
            ),

          if (_isStreaming)
            Positioned(
              top: 40,
              left: 20,
              right: 20,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildGlassBadge(icon: Icons.memory, label: 'FPS: $_fps'),
                  _buildGlassBadge(icon: Icons.camera, label: 'STEP $_scanStep OF 2'),
                ],
              ),
            ),

          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_capturedMeasurements != null)
                  _buildModernResultsCard(unitLabel)
                else if (_isStreaming)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Dynamic Red-to-Green Instruction Banner
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212).withOpacity(0.95),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isAligned ? Colors.greenAccent : Colors.redAccent,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isAligned ? Icons.check_circle : Icons.warning_amber_rounded,
                              color: _isAligned ? Colors.greenAccent : Colors.redAccent,
                              size: 18,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _guidanceInstruction,
                              style: TextStyle(
                                color: _isAligned ? Colors.greenAccent : Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Live Calibration Preview
                      Container(
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121212).withOpacity(0.9),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.white24, width: 1),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Live Calibration Preview",
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                            ),
                            const SizedBox(height: 4),
                            Text("Estimated Height: $_heightDisplay", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            Text("Shoulder Width: $_shoulderDisplay", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  _buildPreStreamCalibrationCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassBadge({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF161616),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 15),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1),
          ),
        ],
      ),
    );
  }

  Widget _buildModernResultsCard(String unitLabel) {
    final double shoulderVal = (_capturedMeasurements!['shoulderWidth'] as num).toDouble();
    final double torsoVal = (_capturedMeasurements!['torsoLength'] as num).toDouble();
    final double heightVal = (_capturedMeasurements!['estimatedHeight'] as num).toDouble();
    final String sizeVal = _capturedMeasurements!['recommendedSize'] as String;
    final String descVal = _capturedMeasurements!['fitDescription'] as String;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.analytics_outlined, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text(
                    'MEASUREMENT REPORT',
                    style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800, letterSpacing: 1.5),
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  children: [
                    _buildUnitToggleButton('IN', !_useMetricUnit),
                    _buildUnitToggleButton('CM', _useMetricUnit),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: Colors.white12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    'SIZE $sizeVal',
                    style: const TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.w900),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RECOMMENDED FIT',
                        style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                      const SizedBox(height: 2),
                      Text(descVal, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricTile('Shoulder', '${_convertUnit(shoulderVal)} $unitLabel', Icons.straighten),
              _buildMetricTile('Torso', '${_convertUnit(torsoVal)} $unitLabel', Icons.height),
              _buildMetricTile('Height', '${_convertUnit(heightVal)} $unitLabel', Icons.person_outline),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _copiedToClipboard ? Colors.grey.shade800 : Colors.white,
                    foregroundColor: _copiedToClipboard ? Colors.white : Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _copyMeasurementsToClipboard,
                  icon: Icon(_copiedToClipboard ? Icons.check : Icons.copy, size: 16),
                  label: Text(
                    _copiedToClipboard ? 'COPIED' : 'COPY REPORT',
                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1E1E1E),
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  setState(() {
                    _capturedMeasurements = null;
                    _copiedToClipboard = false;
                  });
                },
                icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUnitToggleButton(String label, bool active) {
    return GestureDetector(
      onTap: () => setState(() => _useMetricUnit = label == 'CM'),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(color: active ? Colors.black : Colors.white54, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white54, size: 18),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
      ],
    );
  }

  Widget _buildPreStreamCalibrationCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF121212),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(color: Color(0xFF1E1E1E), shape: BoxShape.circle),
            child: const Icon(Icons.accessibility_new, color: Colors.white, size: 32),
          ),
          const SizedBox(height: 16),
          const Text(
            'Smart Measurement AI',
            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter height calibration baseline in inches',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 200,
            child: TextField(
              controller: _heightController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                suffixText: 'INCHES',
                suffixStyle: const TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                filled: true,
                fillColor: const Color(0xFF1E1E1E),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white12)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Colors.white)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _startCameraStream,
              child: const Text(
                'INITIALIZE CAMERA',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- DYNAMIC RED-TO-GREEN ALIGNMENT HUD PAINTER ---
class MonochromePoseHUDPainter extends CustomPainter {
  final List<dynamic>? landmarks;
  final bool isAligned; // true = Green, false = Red
  final double scanProgress;
  final bool isMeasuring;

  MonochromePoseHUDPainter({
    required this.landmarks,
    required this.isAligned,
    required this.scanProgress,
    required this.isMeasuring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final boxWidth = size.width * 0.70;
    final boxHeight = size.height * 0.65;
    final targetRect = Rect.fromCenter(center: center.translate(0, -20), width: boxWidth, height: boxHeight);

    // Dynamic color switching: Red when adjusting, Green when locked!
    final boxColor = isAligned ? Colors.greenAccent : Colors.redAccent;

    final hudPaint = Paint()
      ..color = boxColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isAligned ? 3.0 : 2.0;

    const cornerLength = 30.0;
    canvas.drawLine(targetRect.topLeft, targetRect.topLeft + const Offset(cornerLength, 0), hudPaint);
    canvas.drawLine(targetRect.topLeft, targetRect.topLeft + const Offset(0, cornerLength), hudPaint);
    canvas.drawLine(targetRect.topRight, targetRect.topRight - const Offset(cornerLength, 0), hudPaint);
    canvas.drawLine(targetRect.topRight, targetRect.topRight + const Offset(0, cornerLength), hudPaint);
    canvas.drawLine(targetRect.bottomLeft, targetRect.bottomLeft + const Offset(cornerLength, 0), hudPaint);
    canvas.drawLine(targetRect.bottomLeft, targetRect.bottomLeft - const Offset(0, cornerLength), hudPaint);
    canvas.drawLine(targetRect.bottomRight, targetRect.bottomRight - const Offset(cornerLength, 0), hudPaint);
    canvas.drawLine(targetRect.bottomRight, targetRect.bottomRight - const Offset(0, cornerLength), hudPaint);

    final scanY = targetRect.top + (targetRect.height * scanProgress);
    final scanLaserPaint = Paint()
      ..color = isAligned ? Colors.greenAccent : Colors.white70
      ..strokeWidth = isMeasuring ? 3.0 : 2.0;

    canvas.drawLine(Offset(targetRect.left + 20, scanY), Offset(targetRect.right - 20, scanY), scanLaserPaint);

    if (landmarks != null) {
      final linePaint = Paint()..color = boxColor.withOpacity(0.8)..strokeWidth = 2.0;
      final nodePaint = Paint()..color = boxColor..style = PaintingStyle.fill;

      final connections = [
        [11, 12], [11, 23], [12, 24],
        [11, 13], [13, 15], [12, 14], [14, 16],
      ];

      for (var pair in connections) {
        if (pair[0] < landmarks!.length && pair[1] < landmarks!.length) {
          final p1 = _getOffset(landmarks![pair[0]], size);
          final p2 = _getOffset(landmarks![pair[1]], size);
          canvas.drawLine(p1, p2, linePaint);
        }
      }

      for (var lm in landmarks!) {
        final pos = _getOffset(lm, size);
        canvas.drawCircle(pos, 3.5, nodePaint);
      }
    }
  }

  Offset _getOffset(dynamic lm, Size size) {
    return Offset(
      (lm['x'] as num).toDouble() * size.width,
      (lm['y'] as num).toDouble() * size.height,
    );
  }

  @override
  bool shouldRepaint(covariant MonochromePoseHUDPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.isAligned != isAligned ||
        oldDelegate.isMeasuring != isMeasuring ||
        oldDelegate.scanProgress != scanProgress;
  }
}