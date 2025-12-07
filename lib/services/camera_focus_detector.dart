import 'package:camera/camera.dart';
// ignore: unused_import
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

/// Lightweight focus/scene-change detector with:
/// - Center ROI sampling
/// - Laplacian focus measure (sharper than luminance variance)
/// - Motion gating (prevents firing when moving)
/// - Stability over N frames
class CameraFocusDetector {
  final void Function() onFocus;
  final void Function(
      {required double sharpness,
      required double dynThresh,
      required double motion,
      required double edgeDensity,
      required double aspect,
      required bool hasRect})? onMetrics;

  // ROI: percent of width/height (center crop)
  final double roiWidthFraction;
  final double roiHeightFraction;

  // Sampling stride inside ROI (pixels)
  final int stride;

  // Fire when sharpness exceeds dynamic threshold AND motion is low for N frames
  final double minSharpness; // floor for sharpness threshold
  final double motionThreshold; // average abs diff threshold (0-255)
  final int stableFrames; // consecutive frames required
  final Duration cooldown; // min time between triggers

  // Internal state
  DateTime? _lastTriggered;
  bool _disposed = false;

  // Rolling stability
  int _stableCount = 0;
  double _emaSharpness = 0; // exponential moving average for dynamic threshold

  // Last sampled ROI (downsampled) for motion diff
  List<int>? _lastSample;

  CameraFocusDetector({
    required this.onFocus,
    this.onMetrics,
    this.roiWidthFraction = 0.6,
    this.roiHeightFraction = 0.6,
    this.stride = 4,
    this.minSharpness = 22.0,
    this.motionThreshold = 6.0,
    this.stableFrames = 3,
    this.cooldown = const Duration(seconds: 2),
  });

  void dispose() {
    _disposed = true;
    _lastSample = null;
  }

  void handleImage(CameraImage img) {
    if (_disposed) return;

    final now = DateTime.now();
    if (_lastTriggered != null && now.difference(_lastTriggered!) < cooldown) {
      return;
    }
    if (img.planes.isEmpty) return;

    final yPlane = img.planes[0];
    final bytes = yPlane.bytes;
    final bytesPerRow = yPlane.bytesPerRow;
    final width = img.width;
    final height = img.height;

    // Center ROI
    final rw = (width * roiWidthFraction).clamp(16, width.toDouble()).toInt();
    final rh =
        (height * roiHeightFraction).clamp(16, height.toDouble()).toInt();
    final rx = ((width - rw) / 2).floor();
    final ry = ((height - rh) / 2).floor();

    // Downsampled sampling grid with stride; keep a compact vector for motion
    final s = math.max(2, stride);
    final sample = <int>[];
    double lapSum = 0;
    double lapSum2 = 0;
    int count = 0;

    // 3x3 Laplacian on Y (grayscale), approximate: L = 4*c - (t+b+l+r)
    // Use abs(L) and variance of L as focus measure.
    int pix(int x, int y) {
      final xx = x.clamp(0, width - 1);
      final yy = y.clamp(0, height - 1);
      return bytes[yy * bytesPerRow + xx] & 0xFF;
    }

    for (int y = ry + 1; y < ry + rh - 1; y += s) {
      for (int x = rx + 1; x < rx + rw - 1; x += s) {
        final c = pix(x, y);
        final t = pix(x, y - 1);
        final b = pix(x, y + 1);
        final l = pix(x - 1, y);
        final r = pix(x + 1, y);
        final lap = (4 * c - t - b - l - r).toDouble();
        final al = lap.abs();
        lapSum += al;
        lapSum2 += lap * lap;
        count++;

        // Small signature for motion diff (just center pixel)
        sample.add(c);
      }
    }

    if (count < 8) return;

    final meanAbsLap = lapSum / count; // edge strength
    // ignore: unused_local_variable
    final varLap = (lapSum2 / count) -
        (meanAbsLap * meanAbsLap); // keep as-is; using meanAbsLap already

    // Motion: average absolute difference vs previous sample vector
    double motion = 0;
    if (_lastSample != null && _lastSample!.length == sample.length) {
      double diffSum = 0;
      for (int i = 0; i < sample.length; i++) {
        diffSum += (sample[i] - _lastSample![i]).abs();
      }
      motion = diffSum / sample.length;
    }
    _lastSample = sample;

    // Count edge pixels above a small Laplacian threshold
    int edgeCount = 0;
    const edgeMinLap = 6.0; // lower to detect lighter card edges
    for (int y = ry + 1; y < ry + rh - 1; y += s) {
      for (int x = rx + 1; x < rx + rw - 1; x += s) {
        final c = pix(x, y);
        final t = pix(x, y - 1);
        final b = pix(x, y + 1);
        final l = pix(x - 1, y);
        final r = pix(x + 1, y);
        final lap = (4 * c - t - b - l - r).abs().toDouble();
        if (lap >= edgeMinLap) edgeCount++;
      }
    }
    final totalSamples =
        ((rh - 2) ~/ s) * ((rw - 2) ~/ s); // approximate sampled points
    final edgeDensity =
        totalSamples > 0 ? edgeCount / totalSamples : 0.0; // 0..1

    // Edge distribution: compare border edges vs inner edges to estimate rectangular borders.
    int borderEdges = 0, innerEdges = 0;
    for (int y = ry + 1; y < ry + rh - 1; y += s) {
      for (int x = rx + 1; x < rx + rw - 1; x += s) {
        final c = pix(x, y);
        final t = pix(x, y - 1);
        final b = pix(x, y + 1);
        final l = pix(x - 1, y);
        final r = pix(x + 1, y);
        final lap = (4 * c - t - b - l - r).abs().toDouble();
        if (lap < edgeMinLap) continue;
        final nearBorder = (x - rx) < s ||
            (rx + rw - x) < s ||
            (y - ry) < s ||
            (ry + rh - y) < s;
        if (nearBorder) {
          borderEdges++;
        } else {
          innerEdges++;
        }
      }
    }
    // Heuristic: a card produces strong inner edges (printed text/logo) and consistent straight borders.
    final borderRatio = borderEdges + innerEdges > 0
        ? borderEdges / (borderEdges + innerEdges)
        : 0.0;
    // Estimate aspect ratio of dominant edges by comparing horizontal vs vertical gradients
    double hGradSum = 0, vGradSum = 0;
    for (int y = ry + 1; y < ry + rh - 1; y += s) {
      for (int x = rx + 1; x < rx + rw - 1; x += s) {
        final lpx = (pix(x + 1, y) - pix(x - 1, y)).abs();
        final vpx = (pix(x, y + 1) - pix(x, y - 1)).abs();
        hGradSum += lpx;
        vGradSum += vpx;
      }
    }
    final aspect = vGradSum > 1
        ? (hGradSum / vGradSum)
        : 1.0; // ~width/height bias of edges

    // Determine if a rectangular card likely present
    final hasRect = edgeDensity > 0.12 &&
        borderRatio > 0.20 &&
        aspect > 0.60 &&
        aspect < 1.80;

    // Update EMA for dynamic threshold (alpha small for smoothing)
    const alpha = 0.2;
    _emaSharpness = (_emaSharpness == 0)
        ? meanAbsLap
        : (alpha * meanAbsLap + (1 - alpha) * _emaSharpness);

    // Dynamic sharpness threshold
    final dynThresh = math.max(minSharpness, _emaSharpness * 1.05 + 0.5);

    final sharpEnough = meanAbsLap >= dynThresh;
    final motionLow = motion <= motionThreshold;

    // Emit metrics for logging/overlay
    if (onMetrics != null) {
      onMetrics!(
        sharpness: meanAbsLap,
        dynThresh: dynThresh,
        motion: motion,
        edgeDensity: edgeDensity,
        aspect: aspect,
        hasRect: hasRect,
      );
    }

    if (sharpEnough && motionLow && hasRect) {
      _stableCount++;
    } else {
      _stableCount = 0;
    }

    // debug tuning (uncomment when needed)
    // debugPrint('[Focus] meanAbsLap=${meanAbsLap.toStringAsFixed(1)} '
    //     'dyn=${dynThresh.toStringAsFixed(1)} motion=${motion.toStringAsFixed(1)} '
    //     'stable=$_stableCount/$stableFrames');

    if (_stableCount >= stableFrames) {
      _stableCount = 0;
      _lastTriggered = now;
      try {
        onFocus();
      } catch (_) {}
    }
  }
}
