import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

// Lightweight focus/scene-change detector based on luminance variance.
// Call [handleImage] from camera image stream. It will call [onFocus]
// when variance exceeds [varianceThreshold] and [cooldown] has elapsed.
class CameraFocusDetector {
  final void Function() onFocus;
  final double varianceThreshold;
  final int step;
  final Duration cooldown;

  DateTime? _lastTriggered;
  bool _disposed = false;

  CameraFocusDetector({
    required this.onFocus,
    this.varianceThreshold = 150.0,
    this.step = 20,
    this.cooldown = const Duration(seconds: 2),
  });

  void handleImage(CameraImage img) {
    if (_disposed) return;

    final now = DateTime.now();
    if (_lastTriggered != null && now.difference(_lastTriggered!) < cooldown) {
      return;
    }

    // Use Y (luminance) plane for a fast variance heuristic.
    if (img.planes.isEmpty) return;
    final yPlane = img.planes[0].bytes;
    int count = 0;
    double sum = 0;
    double sum2 = 0;
    final s = step.clamp(1, yPlane.length);

    for (int i = 0; i < yPlane.length; i += s) {
      final v = yPlane[i].toUnsigned(0);
      sum += v;
      sum2 += v * v;
      count++;
    }

    if (count < 2) return;
    final mean = sum / count;
    final variance = (sum2 / count) - (mean * mean);

    // debugPrint(
    // '[FocusDetector] variance=${variance.toStringAsFixed(1)} threshold=$varianceThreshold');

    if (variance > varianceThreshold) {
      _lastTriggered = now;

      // debugPrint('[FocusDetector] triggered focus callback');
      try {
        onFocus();
      } catch (_) {}
    }
  }

  void dispose() {
    _disposed = true;
  }
}
