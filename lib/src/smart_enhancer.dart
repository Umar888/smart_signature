import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'geometry.dart';
import 'signature_data.dart';

/// Turns a raw signature into a cleaner one.
///
/// Implement this to plug in your own enhancement, for example an ML model.
abstract class SignatureEnhancer {
  const SignatureEnhancer();

  /// Runs on the live pad after every stroke. It must not move ink around
  /// as a whole (rotate, re-center), or the user's next stroke would land
  /// in the wrong place relative to what they see.
  SignatureData enhance(SignatureData data);

  /// Runs on export. Can do whole-signature changes like straightening.
  SignatureData finalize(SignatureData data) => enhance(data);
}

/// Knobs for [SmartEnhancer].
@immutable
class EnhanceOptions {
  const EnhanceOptions({
    this.smoothing = 0.5,
    this.removeHooks = true,
    this.removeStrayMarks = true,
    this.straighten = true,
    this.maxTilt = 20,
  }) : assert(smoothing >= 0 && smoothing <= 1);

  /// 0 keeps the lines as drawn, 1 irons out every wobble.
  final double smoothing;

  /// Trims the little ticks left where the pen lands and lifts.
  final bool removeHooks;

  /// Drops tiny accidental marks away from the signature. Dots inside it,
  /// like on an i, are kept.
  final bool removeStrayMarks;

  /// Levels a slanted baseline on export.
  final bool straighten;

  /// Signatures tilted more than this many degrees are left alone, the
  /// slant is probably intentional.
  final double maxTilt;

  EnhanceOptions copyWith({
    double? smoothing,
    bool? removeHooks,
    bool? removeStrayMarks,
    bool? straighten,
    double? maxTilt,
  }) =>
      EnhanceOptions(
        smoothing: smoothing ?? this.smoothing,
        removeHooks: removeHooks ?? this.removeHooks,
        removeStrayMarks: removeStrayMarks ?? this.removeStrayMarks,
        straighten: straighten ?? this.straighten,
        maxTilt: maxTilt ?? this.maxTilt,
      );

  @override
  bool operator ==(Object other) =>
      other is EnhanceOptions &&
      other.smoothing == smoothing &&
      other.removeHooks == removeHooks &&
      other.removeStrayMarks == removeStrayMarks &&
      other.straighten == straighten &&
      other.maxTilt == maxTilt;

  @override
  int get hashCode => Object.hash(
      smoothing, removeHooks, removeStrayMarks, straighten, maxTilt);
}

/// On-device enhancement: removes jitter, pen hooks and stray marks, refits
/// each stroke as a smooth curve and levels the baseline on export.
///
/// Pure Dart geometry, so it's instant, works offline and the signature
/// never leaves the device.
class SmartEnhancer extends SignatureEnhancer {
  const SmartEnhancer({this.options = const EnhanceOptions()});

  final EnhanceOptions options;

  // all distances in logical pixels
  static const double _spacing = 1;
  static const double _detectSigma = 1.5;
  static const int _hookNeighbourhood = 4;
  static const double _hookMaxLength = 14;
  static const double _hookMaxShare = 0.2;
  static const double _hookMinAngle = 65 * math.pi / 180;
  static const double _shortStroke = 8;
  static const double _strayMaxShare = 0.2;
  static const double _strayMargin = 0.25;
  static const double _minTilt = 0.5;

  @override
  SignatureData enhance(SignatureData data) {
    var strokes = data.strokes;
    if (options.removeStrayMarks) strokes = _withoutStrayMarks(strokes);
    return SignatureData([for (final s in strokes) enhanceStroke(s)]);
  }

  @override
  SignatureData finalize(SignatureData data) {
    final enhanced = enhance(data);
    return options.straighten ? _straightened(enhanced) : enhanced;
  }

  /// The per-stroke part of [enhance].
  SignatureStroke enhanceStroke(SignatureStroke stroke) {
    final points = stroke.points;
    if (points.length < 2) return stroke;
    if (stroke.isDot) {
      final c = stroke.bounds.center;
      return SignatureStroke([points.first.copyWith(x: c.dx, y: c.dy)]);
    }
    var path = resample(points, _spacing);
    if (stroke.length < _shortStroke) {
      return SignatureStroke(gaussianSmooth(path, _detectSigma));
    }

    // find hooks on a lightly smoothed copy, single pixel jitter would
    // otherwise look like sharp turns
    final detect = gaussianSmooth(path, _detectSigma);
    if (options.removeHooks) {
      final (start, end) = _hookFreeRange(detect, stroke.length);
      path = path.sublist(start, end + 1);
    }
    final s = options.smoothing;
    if (s > 0) {
      path = gaussianSmooth(path, 1 + s * 6);
      // dropping points within epsilon and refitting a spline flattens the
      // low frequency wobble a blur alone leaves behind
      path = catmullRom(simplify(path, 0.15 + s), _spacing);
    }
    return SignatureStroke(path);
  }

  (int, int) _hookFreeRange(List<SignaturePoint> path, double length) {
    final window = math.min(_hookMaxLength, length * _hookMaxShare);
    final reach = (window / _spacing).floor();
    const k = _hookNeighbourhood;
    if (path.length < reach * 2 + k * 4) return (0, path.length - 1);

    int sharpest(Iterable<int> indices) {
      var best = -1;
      var bestAngle = _hookMinAngle;
      for (final i in indices) {
        final angle =
            turnAngle(path[i - k].offset, path[i].offset, path[i + k].offset);
        if (angle > bestAngle) {
          bestAngle = angle;
          best = i;
        }
      }
      return best;
    }

    final last = path.length - 1;
    final start = sharpest([for (var i = k; i <= reach; i++) i]);
    final end = sharpest([for (var i = last - k; i >= last - reach; i--) i]);
    return (start == -1 ? 0 : start, end == -1 ? last : end);
  }

  List<SignatureStroke> _withoutStrayMarks(List<SignatureStroke> strokes) {
    if (strokes.length < 2) return strokes;
    final longest = strokes.map((s) => s.length).reduce(math.max);
    if (longest == 0) return strokes;
    final major = strokes.where((s) => s.length >= longest * _strayMaxShare);
    final box =
        major.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));
    final area = box.inflate(math.max(box.height, 20) * _strayMargin);
    return [
      for (final s in strokes)
        if (s.length >= longest * _strayMaxShare ||
            area.overlaps(s.bounds) ||
            area.contains(s.bounds.center))
          s,
    ];
  }

  SignatureData _straightened(SignatureData data) {
    final points = [for (final s in data.strokes) ...s.points];
    if (points.length < 10) return data;
    final bounds = data.bounds;
    // a tall or square shape has no meaningful baseline
    if (bounds.width < bounds.height * 1.5) return data;
    final tilt = _principalAngle(points);
    final degrees = tilt.abs() * 180 / math.pi;
    if (degrees < _minTilt || degrees > options.maxTilt) return data;
    final center = bounds.center;
    return SignatureData([
      for (final s in data.strokes)
        SignatureStroke(rotate(s.points, -tilt, center))
    ]);
  }

  /// Direction of the main axis of the point cloud, which for a signature is
  /// the writing direction.
  double _principalAngle(List<SignaturePoint> points) {
    var mx = 0.0, my = 0.0;
    for (final p in points) {
      mx += p.x;
      my += p.y;
    }
    mx /= points.length;
    my /= points.length;
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (final p in points) {
      final dx = p.x - mx, dy = p.y - my;
      sxx += dx * dx;
      syy += dy * dy;
      sxy += dx * dy;
    }
    return 0.5 * math.atan2(2 * sxy, sxx - syy);
  }
}
