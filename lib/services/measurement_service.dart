import 'dart:math';

class MeasurementService {
  static Map<String, double> computeMeasurements(
    List<dynamic> landmarks, {
    double knownHeightInches = 68.0, // Default to 5'8" if not provided
  }) {
    if (landmarks.length <= 28) return {};

    final leftShoulder = landmarks[11];
    final rightShoulder = landmarks[12];
    final leftHip = landmarks[23];
    final rightHip = landmarks[24];
    final leftAnkle = landmarks[27];

    double shoulderDist = _calculateDistance(
      (leftShoulder['x'] as num).toDouble(), (leftShoulder['y'] as num).toDouble(),
      (rightShoulder['x'] as num).toDouble(), (rightShoulder['y'] as num).toDouble(),
    );

    double torsoDist = _calculateDistance(
      ((leftShoulder['x'] + rightShoulder['x']) / 2), ((leftShoulder['y'] + rightShoulder['y']) / 2),
      ((leftHip['x'] + rightHip['x']) / 2), ((leftHip['y'] + rightHip['y']) / 2),
    );

    double fullBodyDist = _calculateDistance(
      ((leftShoulder['x'] + rightShoulder['x']) / 2), ((leftShoulder['y'] + rightShoulder['y']) / 2),
      (leftAnkle['x'] as num).toDouble(), (leftAnkle['y'] as num).toDouble(),
    );

    // Prevent division by zero if user is too far or not fully visible
    if (fullBodyDist <= 0.0) return {};

    // Dynamic scale factor derived from user's known height vs detected pixel height
    double scaleFactor = knownHeightInches / fullBodyDist;

    double estimatedShoulderWidthInches = shoulderDist * scaleFactor * 0.9; // anatomical correction factor
    double estimatedTorsoHeightInches = torsoDist * scaleFactor;

    return {
      'shoulderWidth': double.parse(estimatedShoulderWidthInches.toStringAsFixed(1)),
      'torsoLength': double.parse(estimatedTorsoHeightInches.toStringAsFixed(1)),
      'estimatedHeight': double.parse(knownHeightInches.toStringAsFixed(1)),
    };
  }

  static double _calculateDistance(double x1, double y1, double x2, double y2) {
    return sqrt(pow(x2 - x1, 2) + pow(y2 - y1, 2));
  }

  static bool checkAlignment(List<dynamic> landmarks) {
    if (landmarks.length <= 28) return false;
    for (int idx in [11, 12, 23, 24, 27, 28]) {
      final lm = landmarks[idx];
      final visibility = (lm['visibility'] as num?)?.toDouble() ?? 1.0;
      if (visibility < 0.5) return false;
    }
    return true;
  }
}