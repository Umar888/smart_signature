import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// A sampled point of a stroke, in logical pixels.
@immutable
class SignaturePoint {
  const SignaturePoint(this.x, this.y, {this.time = 0, this.pressure = 0.5});

  /// Reads the `[x, y, time, pressure]` list written by [toJson].
  factory SignaturePoint.fromJson(List<dynamic> json) => SignaturePoint(
        (json[0] as num).toDouble(),
        (json[1] as num).toDouble(),
        time: json.length > 2 ? (json[2] as num).toDouble() : 0,
        pressure: json.length > 3 ? (json[3] as num).toDouble() : 0.5,
      );

  final double x;
  final double y;

  /// Milliseconds from an arbitrary origin. Only differences matter, they
  /// drive the speed based ink width.
  final double time;

  /// 0 to 1. Touch screens usually report a constant value, styluses vary it.
  final double pressure;

  Offset get offset => Offset(x, y);

  SignaturePoint copyWith(
          {double? x, double? y, double? time, double? pressure}) =>
      SignaturePoint(
        x ?? this.x,
        y ?? this.y,
        time: time ?? this.time,
        pressure: pressure ?? this.pressure,
      );

  /// Linear interpolation of every field.
  static SignaturePoint lerp(SignaturePoint a, SignaturePoint b, double t) =>
      SignaturePoint(
        a.x + (b.x - a.x) * t,
        a.y + (b.y - a.y) * t,
        time: a.time + (b.time - a.time) * t,
        pressure: a.pressure + (b.pressure - a.pressure) * t,
      );

  List<num> toJson() =>
      [_round(x), _round(y), _round(time), _round(pressure, 3)];

  @override
  bool operator ==(Object other) =>
      other is SignaturePoint &&
      other.x == x &&
      other.y == y &&
      other.time == time &&
      other.pressure == pressure;

  @override
  int get hashCode => Object.hash(x, y, time, pressure);

  @override
  String toString() => 'SignaturePoint($x, $y)';
}

/// One continuous pen-down to pen-up line.
@immutable
class SignatureStroke {
  SignatureStroke(List<SignaturePoint> points)
      : points = List.unmodifiable(points);

  factory SignatureStroke.fromJson(List<dynamic> json) => SignatureStroke(
      [for (final p in json) SignaturePoint.fromJson(p as List<dynamic>)]);

  final List<SignaturePoint> points;

  /// Path length in logical pixels.
  late final double length = _length(points);

  late final Rect bounds = _bounds(points);

  /// A tap rather than a line, like the dot on an i.
  bool get isDot => length < _dotLength;

  List<List<num>> toJson() => [for (final p in points) p.toJson()];
}

/// A whole signature: its strokes in drawing order.
@immutable
class SignatureData {
  SignatureData(List<SignatureStroke> strokes)
      : strokes = List.unmodifiable(strokes);

  /// Reads the map written by [toJson].
  factory SignatureData.fromJson(Map<String, dynamic> json) => SignatureData([
        for (final s in json['strokes'] as List<dynamic>)
          SignatureStroke.fromJson(s as List<dynamic>),
      ]);

  static final empty = SignatureData(const []);

  final List<SignatureStroke> strokes;

  bool get isEmpty => strokes.isEmpty;
  bool get isNotEmpty => strokes.isNotEmpty;

  /// Bounds of the stroke centerlines, [Rect.zero] when empty.
  Rect get bounds => strokes.isEmpty
      ? Rect.zero
      : strokes.map((s) => s.bounds).reduce((a, b) => a.expandToInclude(b));

  Map<String, Object> toJson() => {
        'version': 1,
        'strokes': [for (final s in strokes) s.toJson()],
      };
}

// strokes shorter than this are treated as a single tap
const double _dotLength = 1.5;

double _length(List<SignaturePoint> points) {
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += (points[i].offset - points[i - 1].offset).distance;
  }
  return total;
}

Rect _bounds(List<SignaturePoint> points) {
  if (points.isEmpty) return Rect.zero;
  var minX = points.first.x, maxX = minX, minY = points.first.y, maxY = minY;
  for (final p in points) {
    minX = math.min(minX, p.x);
    maxX = math.max(maxX, p.x);
    minY = math.min(minY, p.y);
    maxY = math.max(maxY, p.y);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

num _round(double v, [int digits = 2]) {
  final f = math.pow(10, digits);
  final r = (v * f).round() / f;
  return r == r.roundToDouble() ? r.toInt() : r;
}
