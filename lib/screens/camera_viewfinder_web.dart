import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
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

  bool _isAligned = false;
  Map<String, dynamic>? _capturedMeasurements;
  bool _isMeasuring = false;
  bool _copiedToClipboard = false;
  bool _useMetricUnit = false;

  int _frameCount = 0;
  int _fps = 0;
  Timer? _fpsTimer;

  late AnimationController _scanAnimationController;
  final TextEditingController _heightController =
      TextEditingController(text: '68');

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
          _isAligned = landmarks != null
              ? MeasurementService.checkAlignment(landmarks)
              : false;
        });
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

  Future<void> _startCameraStream() async {
    setState(() => _errorMessage = null);

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw 'Camera API not supported in this browser context.';
      }

      final mediaStream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode' : {'ideal':'environment'}

        },
        'audio': false,
      });

      if (mediaStream != null && _videoElement != null) {
        _videoElement!.srcObject = mediaStream;
        await _videoElement!.play();
        if (mounted) {
          setState(() => _isStreaming = true);
          _startPoseInferenceLoop();
        }
      } else {
        throw 'Media stream object returned null from browser.';
      }
    } catch (e) {
      String errText = e.toString();
      if (errText.contains('NotAllowedError') ||
          errText.contains('Permission denied')) {
        errText =
            'Camera permission denied. Click the camera icon in your Chrome address bar to allow access.';
      } else if (errText.contains('NotFoundError')) {
        errText = 'No webcam hardware detected on this device.';
      }

      if (mounted) {
        setState(() => _errorMessage = errText);
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

  void _triggerMeasurementScan() async {
    if (_latestLandmarks == null || !_isAligned) return;

    setState(() {
      _isMeasuring = true;
      _copiedToClipboard = false;
    });

    await Future.delayed(const Duration(seconds: 2));

    double knownHeight = double.tryParse(_heightController.text) ?? 68.0;
    final results = MeasurementService.computeMeasurements(
      _latestLandmarks!,
      knownHeightInches: knownHeight,
    );

    if (mounted) {
      setState(() {
        _capturedMeasurements = results;
        _isMeasuring = false;
      });
    }
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
      backgroundColor: const Color(0xFF0A0E1A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isStreaming)
            HtmlElementView(viewType: _viewId)
          else
            Container(color: const Color(0xFF0A0E1A)),

          if (_isStreaming)
            AnimatedBuilder(
              animation: _scanAnimationController,
              builder: (context, child) {
                return CustomPaint(
                  painter: FuturisticPoseHUDPainter(
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
                  _buildGlassBadge(
                    icon: Icons.memory,
                    label: 'FPS: $_fps',
                    color: Colors.cyanAccent,
                  ),
                  _buildGlassBadge(
                    icon: _isAligned
                        ? Icons.check_circle_outline
                        : Icons.filter_center_focus,
                    label: _isAligned ? 'Target Locked' : 'Searching Target',
                    color:
                        _isAligned ? Colors.greenAccent : Colors.orangeAccent,
                  ),
                ],
              ),
            ),

          if (_isStreaming && _capturedMeasurements == null)
            Positioned(
              top: 100,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: _isAligned
                            ? Colors.greenAccent.withOpacity(0.8)
                            : Colors.yellowAccent.withOpacity(0.5),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isAligned
                                  ? Colors.greenAccent
                                  : Colors.yellowAccent)
                              .withOpacity(0.2),
                          blurRadius: 15,
                        )
                      ],
                    ),
                    child: Text(
                      _isAligned
                          ? 'READY TO SCAN'
                          : 'ALIGN FULL BODY IN FRAME',
                      style: TextStyle(
                        color: _isAligned
                            ? Colors.greenAccent
                            : Colors.yellowAccent,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  
const SizedBox(height: 12),
ElevatedButton.icon(
  onPressed: () {
    setState(() {
      _isAligned = true; // Instantly forces alignment to true for live demo
    });
  },
  icon: const Icon(Icons.bolt, color: Colors.amber, size: 18),
  label: const Text('Bypass Alignment (Live Demo)'),
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.deepOrange,
    foregroundColor: Colors.white,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  ),
),
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
                  _buildScanActionButton()
                else
                  _buildPreStreamCalibrationCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGlassBadge({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: 10,
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanActionButton() {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: _isAligned
            ? const LinearGradient(
                colors: [Color(0xFF00FF87), Color(0xFF60EFFF)])
            : LinearGradient(
                colors: [Colors.grey.shade800, Colors.grey.shade900]),
        boxShadow: _isAligned
            ? [
                BoxShadow(
                  color: const Color(0xFF00FF87).withOpacity(0.4),
                  blurRadius: 20,
                  spreadRadius: 2,
                )
              ]
            : [],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        ),
        onPressed:
            (_isAligned && !_isMeasuring) ? _triggerMeasurementScan : null,
        child: _isMeasuring
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.black, strokeWidth: 3),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isAligned ? Icons.camera_alt : Icons.lock_outline,
                    color: _isAligned ? Colors.black : Colors.white38,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _isAligned ? 'ANALYZE BODY METRICS' : 'AWAITING ALIGNMENT',
                    style: TextStyle(
                      color: _isAligned ? Colors.black : Colors.white38,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
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
        color: const Color(0xFF0F172A).withOpacity(0.95),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withOpacity(0.15),
            blurRadius: 25,
            spreadRadius: 2,
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.analytics_outlined,
                      color: Colors.cyanAccent, size: 22),
                  SizedBox(width: 10),
                  Text(
                    'AI MEASUREMENT SUMMARY',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
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

          // Size Recommendation Highlight Box
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'SIZE $sizeVal',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'RECOMMENDED RETAIL SIZE',
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        descVal,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Quantitative Body Metrics Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricTile(
                'Shoulder Width',
                '${_convertUnit(shoulderVal)} $unitLabel',
                Icons.straighten,
              ),
              _buildMetricTile(
                'Torso Height',
                '${_convertUnit(torsoVal)} $unitLabel',
                Icons.height,
              ),
              _buildMetricTile(
                'Ref. Height',
                '${_convertUnit(heightVal)} $unitLabel',
                Icons.person_outline,
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _copiedToClipboard
                        ? Colors.blueAccent
                        : Colors.cyanAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: _copyMeasurementsToClipboard,
                  icon: Icon(
                      _copiedToClipboard ? Icons.check_circle : Icons.copy,
                      size: 18),
                  label: Text(
                    _copiedToClipboard ? 'COPIED TO CLIPBOARD' : 'COPY REPORT',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white10,
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  setState(() {
                    _capturedMeasurements = null;
                    _copiedToClipboard = false;
                  });
                },
                icon: const Icon(Icons.refresh, color: Colors.white),
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
          color: active ? Colors.cyanAccent : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.black : Colors.white54,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white38, size: 20),
        const SizedBox(height: 6),
        Text(label,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }

  Widget _buildPreStreamCalibrationCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withOpacity(0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 30,
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.cyanAccent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.accessibility_new,
                color: Colors.cyanAccent, size: 36),
          ),
          const SizedBox(height: 16),
          const Text(
            'Smart Measurement AI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your height for dynamic pixel-to-metric calibration',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: 220,
            child: TextField(
              controller: _heightController,
              keyboardType: TextInputType.number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                suffixText: 'INCHES',
                suffixStyle: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
                filled: true,
                fillColor: Colors.black45,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Colors.cyanAccent),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: _startCameraStream,
              child: const Text(
                'INITIALIZE CAMERA STREAM',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FuturisticPoseHUDPainter extends CustomPainter {
  final List<dynamic>? landmarks;
  final bool isAligned;
  final double scanProgress;
  final bool isMeasuring;

  FuturisticPoseHUDPainter({
    required this.landmarks,
    required this.isAligned,
    required this.scanProgress,
    required this.isMeasuring,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final boxWidth = size.width * 0.65;
    final boxHeight = size.height * 0.75;
    final targetRect =
        Rect.fromCenter(center: center, width: boxWidth, height: boxHeight);

    final hudColor = isAligned ? Colors.greenAccent : Colors.cyanAccent;
    final hudPaint = Paint()
      ..color = hudColor.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    const cornerLength = 30.0;
    canvas.drawLine(targetRect.topLeft,
        targetRect.topLeft + const Offset(cornerLength, 0), hudPaint);
    canvas.drawLine(targetRect.topLeft,
        targetRect.topLeft + const Offset(0, cornerLength), hudPaint);

    canvas.drawLine(targetRect.topRight,
        targetRect.topRight - const Offset(cornerLength, 0), hudPaint);
    canvas.drawLine(targetRect.topRight,
        targetRect.topRight + const Offset(0, cornerLength), hudPaint);

    canvas.drawLine(targetRect.bottomLeft,
        targetRect.bottomLeft + const Offset(cornerLength, 0), hudPaint);
    canvas.drawLine(targetRect.bottomLeft,
        targetRect.bottomLeft - const Offset(0, cornerLength), hudPaint);

    canvas.drawLine(targetRect.bottomRight,
        targetRect.bottomRight - const Offset(cornerLength, 0), hudPaint);
    canvas.drawLine(targetRect.bottomRight,
        targetRect.bottomRight - const Offset(0, cornerLength), hudPaint);

    final scanY = targetRect.top + (targetRect.height * scanProgress);
    final scanLaserPaint = Paint()
      ..color = (isMeasuring ? Colors.greenAccent : Colors.cyanAccent)
          .withOpacity(0.7)
      ..strokeWidth = isMeasuring ? 4.0 : 2.0;

    canvas.drawLine(
      Offset(targetRect.left, scanY),
      Offset(targetRect.right, scanY),
      scanLaserPaint,
    );

    if (landmarks != null) {
      final linePaint = Paint()
        ..color = isAligned
            ? Colors.greenAccent.withOpacity(0.6)
            : Colors.cyanAccent.withOpacity(0.4)
        ..strokeWidth = 2.0;

      final nodePaint = Paint()
        ..color = isAligned ? Colors.greenAccent : Colors.cyanAccent
        ..style = PaintingStyle.fill;

      final connections = [
        [11, 12],
        [11, 23],
        [12, 24],
        [23, 24],
        [11, 13],
        [13, 15],
        [12, 14],
        [14, 16],
        [23, 25],
        [25, 27],
        [24, 26],
        [26, 28],
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
        canvas.drawCircle(pos, 4.0, nodePaint);
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
  bool shouldRepaint(covariant FuturisticPoseHUDPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.isAligned != isAligned ||
        oldDelegate.isMeasuring != isMeasuring ||
        oldDelegate.scanProgress != scanProgress;
  }
}