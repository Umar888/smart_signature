import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_signature/smart_signature.dart';

/// A stroke along [path] sampled every pixel, 1 ms apart, plus seeded noise.
SignatureStroke stroke(
  Offset Function(double t) path, {
  int samples = 200,
  double noise = 0,
  int seed = 1,
}) {
  final random = math.Random(seed);
  return SignatureStroke([
    for (var i = 0; i <= samples; i++)
      () {
        final p = path(i / samples);
        return SignaturePoint(
          p.dx + (random.nextDouble() * 2 - 1) * noise,
          p.dy + (random.nextDouble() * 2 - 1) * noise,
          time: i.toDouble(),
        );
      }(),
  ]);
}

SignatureStroke line(Offset a, Offset b, {double noise = 0, int seed = 1}) =>
    stroke((t) => Offset.lerp(a, b, t)!,
        samples: (b - a).distance.round(), noise: noise, seed: seed);

/// Average second difference: how much the path wiggles from one pixel to
/// the next.
double roughness(SignatureStroke s) {
  final p = s.points;
  var total = 0.0;
  for (var i = 1; i < p.length - 1; i++) {
    total += (p[i - 1].offset - p[i].offset * 2 + p[i + 1].offset).distance;
  }
  return total / (p.length - 2);
}

/// Angle of the line through the first and last point, in degrees.
double slope(SignatureStroke s) {
  final d = s.points.last.offset - s.points.first.offset;
  return math.atan2(d.dy, d.dx) * 180 / math.pi;
}

void main() {
  const enhancer = SmartEnhancer();

  test('removes jitter from a shaky line', () {
    final shaky = line(const Offset(0, 50), const Offset(300, 50), noise: 1.5);
    final smooth = enhancer.enhanceStroke(shaky);
    // the zig-zag you see as shakiness, compared at the same spacing
    expect(roughness(smooth), lessThan(roughness(shaky) / 5));
    final drift = smooth.points.map((p) => (p.y - 50).abs()).reduce(math.max);
    expect(drift, lessThan(1.2));
  });

  test('smoothing 0 keeps the line as drawn', () {
    final shaky = line(const Offset(0, 50), const Offset(300, 50), noise: 1.5);
    const raw = SmartEnhancer(
        options: EnhanceOptions(smoothing: 0, removeHooks: false));
    final kept = raw.enhanceStroke(shaky);
    final error = kept.points.map((p) => (p.y - 50).abs()).reduce(math.max);
    expect(error, greaterThan(0.6));
  });

  test('trims the hook where the pen landed', () {
    // 8px tick down before the real stroke heads right
    final hooked = SignatureStroke([
      ...line(const Offset(0, 8), const Offset(0, 0)).points,
      ...line(const Offset(0, 0), const Offset(200, 0)).points.skip(1),
    ]);
    final cleaned = enhancer.enhanceStroke(hooked);
    expect(cleaned.points.first.y.abs(), lessThan(2));
    expect(cleaned.points.last.offset.dx, closeTo(200, 1));
  });

  test('trims the hook where the pen lifted', () {
    final hooked = SignatureStroke([
      ...line(const Offset(0, 0), const Offset(200, 0)).points,
      ...line(const Offset(200, 0), const Offset(192, -9)).points.skip(1),
    ]);
    final cleaned = enhancer.enhanceStroke(hooked);
    expect(cleaned.points.last.y.abs(), lessThan(2));
    expect(cleaned.points.last.x, greaterThan(190));
  });

  test('keeps a sharp turn in the middle of a stroke', () {
    final vee = SignatureStroke([
      ...line(const Offset(0, 0), const Offset(60, 80)).points,
      ...line(const Offset(60, 80), const Offset(120, 0)).points.skip(1),
    ]);
    final cleaned = enhancer.enhanceStroke(vee);
    final lowest = cleaned.points.map((p) => p.y).reduce(math.max);
    expect(lowest, greaterThan(70));
    expect(cleaned.points.first.offset.distance, lessThan(2));
  });

  test('drops stray marks but keeps dots inside the signature', () {
    final main = line(const Offset(0, 40), const Offset(300, 40));
    final loop = stroke(
        (t) => Offset(120 + 30 * math.cos(t * 2 * math.pi),
            40 + 30 * math.sin(t * 2 * math.pi)),
        samples: 190);
    final iDot = SignatureStroke([const SignaturePoint(150, 0)]);
    final stray = line(const Offset(500, 300), const Offset(503, 302));
    final result = enhancer.enhance(SignatureData([main, loop, iDot, stray]));
    expect(result.strokes, hasLength(3));
    expect(result.strokes.any((s) => s.bounds.center.dx > 400), isFalse);
    expect(result.strokes.any((s) => s.points.length == 1), isTrue);
  });

  test('a single stroke is never treated as stray', () {
    final only = line(const Offset(0, 0), const Offset(2, 2));
    expect(enhancer.enhance(SignatureData([only])).strokes, hasLength(1));
  });

  test('a tap becomes a single dot', () {
    final tap = SignatureStroke(const [
      SignaturePoint(10, 10),
      SignaturePoint(10.4, 10.3),
      SignaturePoint(10.2, 10.6),
    ]);
    final dot = enhancer.enhanceStroke(tap);
    expect(dot.points, hasLength(1));
  });

  group('straighten', () {
    final tilted = line(const Offset(0, 0),
        Offset(300 * math.cos(0.14), 300 * math.sin(0.14))); // ~8 degrees
    final data = SignatureData([tilted]);

    test('levels the baseline on export', () {
      expect(slope(tilted), closeTo(8, 0.5));
      expect(slope(enhancer.finalize(data).strokes.single).abs(), lessThan(1));
    });

    test('leaves the live pad alone', () {
      expect(slope(enhancer.enhance(data).strokes.single), closeTo(8, 0.5));
    });

    test('ignores steep, probably intentional slants', () {
      final steep = SignatureData([
        line(const Offset(0, 0),
            Offset(300 * math.cos(0.6), 300 * math.sin(0.6))),
      ]);
      expect(slope(enhancer.finalize(steep).strokes.single), closeTo(34, 1));
    });

    test('can be switched off', () {
      const keep = SmartEnhancer(options: EnhanceOptions(straighten: false));
      expect(slope(keep.finalize(data).strokes.single), closeTo(8, 0.5));
    });
  });

  test('enhancing twice changes little', () {
    final shaky = line(const Offset(0, 50), const Offset(300, 90), noise: 1);
    final once = enhancer.enhanceStroke(shaky);
    final twice = enhancer.enhanceStroke(once);
    expect(twice.length, closeTo(once.length, once.length * 0.02));
  });

  test('time and pressure follow the resampled points', () {
    final timed = SignatureStroke(const [
      SignaturePoint(0, 0, time: 0, pressure: 0.2),
      SignaturePoint(100, 0, time: 100, pressure: 0.8),
    ]);
    final out = enhancer.enhanceStroke(timed);
    final middle = out.points[out.points.length ~/ 2];
    expect(middle.time, closeTo(middle.x, 2));
    expect(middle.pressure, closeTo(0.2 + 0.6 * middle.x / 100, 0.05));
  });
}
