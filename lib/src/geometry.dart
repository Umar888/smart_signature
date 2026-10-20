import 'dart:math' as math;
import 'dart:ui';

import 'signature_data.dart';

/// Points spaced [spacing] apart along the path, time and pressure interpolated.
/// The last point is always kept so the stroke doesn't lose its reach.
List<SignaturePoint> resample(List<SignaturePoint> points, double spacing) {
  if (points.length < 2) return List.of(points);
  final out = <SignaturePoint>[points.first];
  // distance travelled since the last emitted point
  var carry = 0.0;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    final segment = (b.offset - a.offset).distance;
    if (segment == 0) continue;
    var d = spacing - carry;
    while (d <= segment) {
      out.add(SignaturePoint.lerp(a, b, d / segment));
      d += spacing;
    }
    carry = segment - (d - spacing);
  }
  if ((out.last.offset - points.last.offset).distance < spacing * 0.25) {
    out[out.length - 1] = points.last;
  } else {
    out.add(points.last);
  }
  return out;
}

/// Gaussian blur of the coordinates. The window shrinks symmetrically near
/// the ends, so endpoints stay put instead of being pulled inwards.
List<SignaturePoint> gaussianSmooth(List<SignaturePoint> points, double sigma) {
  final n = points.length;
  if (n < 3 || sigma <= 0) return List.of(points);
  final radius = (sigma * 3).ceil();
  final weights = [
    for (var k = -radius; k <= radius; k++)
      math.exp(-(k * k) / (2 * sigma * sigma))
  ];
  return [
    for (var i = 0; i < n; i++)
      _smoothAt(
          points, weights, i, math.min(radius, math.min(i, n - 1 - i)), radius),
  ];
}

SignaturePoint _smoothAt(List<SignaturePoint> points, List<double> weights,
    int i, int reach, int radius) {
  var sx = 0.0, sy = 0.0, sw = 0.0;
  for (var k = -reach; k <= reach; k++) {
    final w = weights[k + radius];
    sx += points[i + k].x * w;
    sy += points[i + k].y * w;
    sw += w;
  }
  return points[i].copyWith(x: sx / sw, y: sy / sw);
}

/// Ramer-Douglas-Peucker: drops points within [epsilon] of the simplified line.
List<SignaturePoint> simplify(List<SignaturePoint> points, double epsilon) {
  if (points.length < 3) return List.of(points);
  final keep = List<bool>.filled(points.length, false)
    ..first = true
    ..last = true;
  final stack = <(int, int)>[(0, points.length - 1)];
  while (stack.isNotEmpty) {
    final (start, end) = stack.removeLast();
    var maxDistance = 0.0;
    var index = -1;
    for (var i = start + 1; i < end; i++) {
      final d = _distanceToSegment(
          points[i].offset, points[start].offset, points[end].offset);
      if (d > maxDistance) {
        maxDistance = d;
        index = i;
      }
    }
    if (index != -1 && maxDistance > epsilon) {
      keep[index] = true;
      stack
        ..add((start, index))
        ..add((index, end));
    }
  }
  return [
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i]
  ];
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared == 0) return (p - a).distance;
  final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Centripetal Catmull-Rom spline through [points], sampled every [spacing].
/// Centripetal parameterisation avoids the loops and cusps the uniform
/// version makes on uneven point spacing.
List<SignaturePoint> catmullRom(List<SignaturePoint> points, double spacing) {
  if (points.length < 3) return resample(points, spacing);
  final out = <SignaturePoint>[points.first];
  for (var i = 0; i < points.length - 1; i++) {
    final p1 = points[i], p2 = points[i + 1];
    // reflect the neighbour at the ends instead of duplicating a point
    final p0 = i > 0 ? points[i - 1].offset : p1.offset * 2 - p2.offset;
    final p3 = i + 2 < points.length
        ? points[i + 2].offset
        : p2.offset * 2 - p1.offset;
    final steps =
        math.max(1, ((p2.offset - p1.offset).distance / spacing).ceil());
    for (var s = 1; s <= steps; s++) {
      final u = s / steps;
      final position = _centripetal(p0, p1.offset, p2.offset, p3, u);
      out.add(SignaturePoint.lerp(p1, p2, u)
          .copyWith(x: position.dx, y: position.dy));
    }
  }
  return out;
}

Offset _centripetal(Offset p0, Offset p1, Offset p2, Offset p3, double u) {
  double knot(Offset a, Offset b) =>
      math.max(math.sqrt((b - a).distance), 1e-4);
  const t0 = 0.0;
  final t1 = t0 + knot(p0, p1);
  final t2 = t1 + knot(p1, p2);
  final t3 = t2 + knot(p2, p3);
  final t = t1 + (t2 - t1) * u;
  Offset mix(Offset a, Offset b, double ta, double tb) =>
      a * ((tb - t) / (tb - ta)) + b * ((t - ta) / (tb - ta));
  final a1 = mix(p0, p1, t0, t1);
  final a2 = mix(p1, p2, t1, t2);
  final a3 = mix(p2, p3, t2, t3);
  final b1 = mix(a1, a2, t0, t2);
  final b2 = mix(a2, a3, t1, t3);
  return mix(b1, b2, t1, t2);
}

/// How sharply the path turns at [b], from 0 (straight on) to pi (doubling back).
double turnAngle(Offset a, Offset b, Offset c) {
  final u = b - a, v = c - b;
  final lengths = u.distance * v.distance;
  if (lengths == 0) return 0;
  final cos = ((u.dx * v.dx + u.dy * v.dy) / lengths).clamp(-1.0, 1.0);
  return math.acos(cos);
}

/// Rotates every point by [angle] radians around [center].
List<SignaturePoint> rotate(
    List<SignaturePoint> points, double angle, Offset center) {
  final c = math.cos(angle), s = math.sin(angle);
  return [
    for (final p in points)
      p.copyWith(
        x: center.dx + (p.x - center.dx) * c - (p.y - center.dy) * s,
        y: center.dy + (p.x - center.dx) * s + (p.y - center.dy) * c,
      ),
  ];
}
