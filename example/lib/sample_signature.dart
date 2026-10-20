import 'dart:math' as math;
import 'dart:ui';

import 'package:smart_signature/smart_signature.dart';

// A cursive "Umar" with an underline, in a 300 x 120 design box. Each list is
// one stroke's control polygon; corners get rounded before sampling.
const _strokes = [
  // U, starting with a little hook where the pen lands
  [
    Offset(24, 34), Offset(18, 28), Offset(22, 60), Offset(30, 88), //
    Offset(42, 96), Offset(55, 88), Offset(62, 60), Offset(64, 30),
    Offset(64, 58), Offset(68, 86), Offset(76, 94),
  ],
  // mar, ending with a hook where the pen lifts
  [
    Offset(82, 92), Offset(86, 70), Offset(94, 58), Offset(102, 62), //
    Offset(104, 90), Offset(106, 66), Offset(114, 56), Offset(122, 62),
    Offset(124, 92), Offset(128, 80), Offset(140, 62), Offset(150, 64),
    Offset(152, 80), Offset(146, 92), Offset(134, 90), Offset(132, 76),
    Offset(146, 64), Offset(156, 66), Offset(156, 90), Offset(164, 94),
    Offset(168, 70), Offset(172, 64), Offset(176, 92), Offset(178, 70),
    Offset(188, 60), Offset(198, 64), Offset(194, 71),
  ],
  // underline flourish
  [
    Offset(8, 110), Offset(70, 104), Offset(150, 100), Offset(230, 98), //
    Offset(280, 92), Offset(296, 80),
  ],
  // an accidental tap away from the signature
  [Offset(300, 0), Offset(301.5, 0.8)],
];

const _designWidth = 300.0;
const _designBaseline = 100.0;
// px per ms, a relaxed signing speed
const _speed = 0.55;
const _strokeGap = 180.0;

/// A shaky, slightly tilted signature with pen hooks and a stray tap, sized
/// to sit on the baseline of a pad of [size]. Times are in ms from 0.
List<SignatureStroke> sampleStrokes(Size size, {int seed = 7}) {
  final random = math.Random(seed);
  final scale = (size.width - 64) / _designWidth;
  final origin = Offset(32, size.height * 0.68 - _designBaseline * scale);
  const tilt = -6 * math.pi / 180;
  final pivot = Offset(size.width / 2, size.height * 0.68);

  var time = 0.0;
  final strokes = <SignatureStroke>[];
  for (final control in _strokes) {
    final path = _chaikin(control.map((p) => origin + p * scale).toList(), 3);
    final points = <SignaturePoint>[];
    Offset? previous;
    for (final p in _resample(path, 2.5)) {
      if (previous != null) time += (p - previous).distance / _speed;
      previous = p;
      final shaky = _rotate(p, tilt, pivot) +
          Offset(random.nextDouble() - 0.5, random.nextDouble() - 0.5) * 1.8;
      points.add(SignaturePoint(shaky.dx, shaky.dy, time: time));
    }
    strokes.add(SignatureStroke(points));
    time += _strokeGap;
  }
  return strokes;
}

/// Corner cutting, keeps the end points.
List<Offset> _chaikin(List<Offset> points, int rounds) {
  var out = points;
  for (var r = 0; r < rounds; r++) {
    final next = [out.first];
    for (var i = 0; i < out.length - 1; i++) {
      next
        ..add(Offset.lerp(out[i], out[i + 1], 0.25)!)
        ..add(Offset.lerp(out[i], out[i + 1], 0.75)!);
    }
    out = next..add(points.last);
  }
  return out;
}

List<Offset> _resample(List<Offset> path, double spacing) {
  final out = [path.first];
  var carry = 0.0;
  for (var i = 1; i < path.length; i++) {
    final a = path[i - 1], b = path[i];
    final segment = (b - a).distance;
    var d = spacing - carry;
    while (d <= segment) {
      out.add(Offset.lerp(a, b, d / segment)!);
      d += spacing;
    }
    carry = segment - (d - spacing);
  }
  return out..add(path.last);
}

Offset _rotate(Offset p, double angle, Offset pivot) {
  final c = math.cos(angle), s = math.sin(angle);
  final d = p - pivot;
  return pivot + Offset(d.dx * c - d.dy * s, d.dx * s + d.dy * c);
}
