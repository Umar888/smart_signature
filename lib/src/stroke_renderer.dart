import 'dart:math' as math;
import 'dart:ui';

import 'geometry.dart';
import 'signature_data.dart';
import 'signature_style.dart';

/// A filled shape that makes up part of a stroke.
sealed class InkShape {
  const InkShape();
}

/// A tap, or a stroke too short to have a direction.
class InkDot extends InkShape {
  const InkDot(this.center, this.radius);

  final Offset center;
  final double radius;
}

/// A variable width band around a centerline, with round caps.
class InkRibbon extends InkShape {
  const InkRibbon(this.left, this.right, this.startRadius, this.endRadius);

  final List<Offset> left;
  final List<Offset> right;
  final double startRadius;
  final double endRadius;
}

// above this the outline of a single band would fold over itself
const double _splitAngle = 100 * math.pi / 180;
// px per ms where the ballpoint reaches its thinnest
const double _fastSpeed = 2.5;
const double _minWidth = 0.4;

/// Outline shapes for [stroke]. With [ink] off every point gets the plain
/// [SignatureStyle.width], which is how the raw "before" view is drawn.
List<InkShape> inkShapes(SignatureStroke stroke, SignatureStyle style,
    {required bool ink}) {
  final points = stroke.points;
  if (points.isEmpty) return const [];
  final widths = ink
      ? _inkWidths(points, style, stroke.length)
      : List.filled(points.length, style.width);
  if (points.length == 1 || stroke.isDot) {
    final c = points.length == 1 ? points.first.offset : stroke.bounds.center;
    return [InkDot(c, math.max(widths.reduce(math.max) * 0.6, 0.8))];
  }

  final shapes = <InkShape>[];
  var start = 0;
  for (var i = 1; i < points.length - 1; i++) {
    if (turnAngle(
            points[i - 1].offset, points[i].offset, points[i + 1].offset) >
        _splitAngle) {
      shapes.add(_ribbon(points, widths, start, i));
      start = i;
    }
  }
  shapes.add(_ribbon(points, widths, start, points.length - 1));
  return shapes;
}

InkRibbon _ribbon(
    List<SignaturePoint> points, List<double> widths, int from, int to) {
  final left = <Offset>[], right = <Offset>[];
  var tangent = const Offset(1, 0);
  for (var i = from; i <= to; i++) {
    final a = points[i == from ? i : i - 1].offset;
    final b = points[i == to ? i : i + 1].offset;
    final d = b - a;
    if (d.distance > 0) tangent = d / d.distance;
    final normal = Offset(-tangent.dy, tangent.dx) * (widths[i] / 2);
    left.add(points[i].offset + normal);
    right.add(points[i].offset - normal);
  }
  return InkRibbon(left, right, widths[from] / 2, widths[to] / 2);
}

List<double> _inkWidths(
    List<SignaturePoint> points, SignatureStyle style, double length) {
  final n = points.length;
  if (style.ink == InkStyle.marker) return List.filled(n, style.width);

  final duration = points.last.time - points.first.time;
  var minPressure = 1.0, maxPressure = 0.0;
  for (final p in points) {
    minPressure = math.min(minPressure, p.pressure);
    maxPressure = math.max(maxPressure, p.pressure);
  }
  // fingers report a flat pressure, only trust it when it actually varies
  final usePressure = maxPressure - minPressure > 0.05;
  final taper = math.min(length * 0.18, style.width * 5);

  final factors = List<double>.filled(n, 1);
  var speed = 0.0;
  var travelled = 0.0;
  for (var i = 0; i < n; i++) {
    if (i > 0) {
      final step = (points[i].offset - points[i - 1].offset).distance;
      travelled += step;
      final dt = math.max(points[i].time - points[i - 1].time, 1.0);
      // smoothed so one late timestamp doesn't pinch the line
      speed = i == 1 ? step / dt : speed * 0.75 + (step / dt) * 0.25;
    }
    var f = 1.0;
    final slow = duration > 1 ? 1 - _smoothstep(speed / _fastSpeed) : 0.5;
    switch (style.ink) {
      case InkStyle.ballpoint:
        f = 0.6 + 0.7 * slow;
      case InkStyle.fountain:
        final a = points[math.max(i - 1, 0)].offset,
            b = points[math.min(i + 1, n - 1)].offset;
        final direction = math.atan2(b.dy - a.dy, b.dx - a.dx);
        f = (0.25 + 0.95 * math.sin(direction - style.nibAngle).abs()) *
            (0.85 + 0.25 * slow);
      case InkStyle.marker:
        break;
    }
    if (usePressure) f *= 0.6 + 0.8 * points[i].pressure;
    if (taper > 0) {
      final fromEnd = math.min(travelled, length - travelled);
      f *= 0.35 + 0.65 * _easeOut((fromEnd / taper).clamp(0.0, 1.0));
    }
    factors[i] = f;
  }
  // light box blur so the width never jumps between neighbours
  return [
    for (var i = 0; i < n; i++)
      math.max(
        style.width *
            (factors[math.max(i - 1, 0)] +
                factors[i] +
                factors[math.min(i + 1, n - 1)]) /
            3,
        _minWidth,
      ),
  ];
}

double _smoothstep(double x) {
  final t = x.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _easeOut(double t) => 1 - math.pow(1 - t, 3).toDouble();

/// Paints [strokes] onto [canvas].
void paintStrokes(
    Canvas canvas, Iterable<SignatureStroke> strokes, SignatureStyle style,
    {required bool ink}) {
  final paint = Paint()
    ..color = style.color
    ..isAntiAlias = true;
  for (final stroke in strokes) {
    for (final shape in inkShapes(stroke, style, ink: ink)) {
      switch (shape) {
        case InkDot(:final center, :final radius):
          canvas.drawCircle(center, radius, paint);
        case InkRibbon():
          canvas.drawPath(ribbonPath(shape), paint);
      }
    }
  }
}

/// The ribbon outline: left side forward, round cap, right side back, cap.
Path ribbonPath(InkRibbon r) {
  final path = Path()..moveTo(r.left.first.dx, r.left.first.dy);
  void through(List<Offset> points) {
    if (points.length == 2) {
      path.lineTo(points[1].dx, points[1].dy);
      return;
    }
    // quadratic curves through the midpoints keep the outline round
    for (var i = 1; i < points.length - 1; i++) {
      final mid = (points[i] + points[i + 1]) / 2;
      path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
  }

  through(r.left);
  path.arcToPoint(r.right.last,
      radius: Radius.circular(r.endRadius), clockwise: false);
  through(r.right.reversed.toList());
  path.arcToPoint(r.left.first,
      radius: Radius.circular(r.startRadius), clockwise: false);
  return path..close();
}

/// The same outline as [ribbonPath], as SVG path data.
String ribbonSvg(InkRibbon r) {
  final b = StringBuffer('M${_n(r.left.first.dx)} ${_n(r.left.first.dy)}');
  void through(List<Offset> points) {
    for (var i = 1; i < points.length - 1; i++) {
      final mid = (points[i] + points[i + 1]) / 2;
      b.write(
          'Q${_n(points[i].dx)} ${_n(points[i].dy)} ${_n(mid.dx)} ${_n(mid.dy)}');
    }
    b.write('L${_n(points.last.dx)} ${_n(points.last.dy)}');
  }

  void arc(double radius, Offset to) =>
      b.write('A${_n(radius)} ${_n(radius)} 0 0 0 ${_n(to.dx)} ${_n(to.dy)}');

  through(r.left);
  arc(r.endRadius, r.right.last);
  through(r.right.reversed.toList());
  arc(r.startRadius, r.left.first);
  return (b..write('Z')).toString();
}

String _n(double v) {
  final s = v.toStringAsFixed(2);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Widest the ink can get for [style], used to pad export bounds.
double maxInkWidth(SignatureStyle style) =>
    style.width * (style.ink == InkStyle.fountain ? 1.6 : 2.2);
