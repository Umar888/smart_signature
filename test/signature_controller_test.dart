import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_signature/smart_signature.dart';

SignatureStroke dash(double y) => SignatureStroke([
      for (var x = 0; x <= 120; x += 4)
        SignaturePoint(x.toDouble(), y, time: x.toDouble()),
    ]);

void main() {
  group('history', () {
    test('undo, redo and clear', () {
      final c = SignatureController();
      expect(c.isEmpty, isTrue);
      expect(c.canUndo, isFalse);

      c.load(SignatureData([dash(10)]));
      c.load(SignatureData([dash(10), dash(30)]));
      expect(c.strokes, hasLength(2));

      c.undo();
      expect(c.strokes, hasLength(1));
      expect(c.canRedo, isTrue);
      c.redo();
      expect(c.strokes, hasLength(2));

      c.clear();
      expect(c.isEmpty, isTrue);
      c.undo();
      expect(c.strokes, hasLength(2), reason: 'clear is undoable');
    });

    test('a new stroke drops the redo branch', () {
      final c = SignatureController()
        ..beginStroke(const SignaturePoint(0, 0))
        ..addPoint(const SignaturePoint(50, 0, time: 20))
        ..endStroke()
        ..undo();
      expect(c.canRedo, isTrue);
      c
        ..beginStroke(const SignaturePoint(0, 10))
        ..addPoint(const SignaturePoint(50, 10, time: 20))
        ..endStroke();
      expect(c.canRedo, isFalse);
      expect(c.strokes.single.points.first.y, 10);
    });

    test('cancelled strokes are not kept', () {
      final c = SignatureController()
        ..beginStroke(const SignaturePoint(0, 0))
        ..addPoint(const SignaturePoint(40, 0))
        ..cancelStroke();
      expect(c.isEmpty, isTrue);
      expect(c.activePoints, isNull);
    });

    test('points closer than half a pixel are skipped', () {
      final c = SignatureController()
        ..beginStroke(const SignaturePoint(0, 0))
        ..addPoint(const SignaturePoint(0.2, 0.1))
        ..addPoint(const SignaturePoint(5, 0))
        ..endStroke();
      expect(c.strokes.single.points, hasLength(2));
    });
  });

  test('listeners hear about strokes, not every point', () {
    final c = SignatureController();
    var calls = 0;
    c.addListener(() => calls++);
    c.beginStroke(const SignaturePoint(0, 0));
    for (var i = 1; i < 50; i++) {
      c.addPoint(SignaturePoint(i * 2.0, 0));
    }
    expect(calls, 0);
    c.endStroke();
    expect(calls, 1);
  });

  test('display follows the enhance switch', () {
    final c = SignatureController(initial: SignatureData([dash(10)]));
    final raw = c.strokes.single;
    expect(identical(c.displayStrokes.single, raw), isFalse);
    c.enhance = false;
    expect(identical(c.displayStrokes.single, raw), isTrue);
  });

  test('JSON round trip', () {
    final data = SignatureData([
      dash(10),
      SignatureStroke(
          const [SignaturePoint(5.123, 6.456, time: 7, pressure: 0.25)]),
    ]);
    final decoded = SignatureData.fromJson(
        jsonDecode(jsonEncode(data.toJson())) as Map<String, dynamic>);
    expect(decoded.strokes, hasLength(2));
    expect(decoded.strokes.first.points, data.strokes.first.points);
    final p = decoded.strokes.last.points.single;
    expect((p.x, p.y, p.time, p.pressure), (5.12, 6.46, 7.0, 0.25));
  });

  group('export', () {
    final c = SignatureController(initial: SignatureData([dash(10), dash(40)]));

    test('empty pad exports nothing', () async {
      final empty = SignatureController();
      expect(empty.toSvg(), isNull);
      expect(await empty.toPngBytes(), isNull);
    });

    test('SVG is cropped to the ink and uses the ink colour', () {
      c.style = const SignatureStyle(color: Color(0xFF112233));
      final svg = c.toSvg(padding: 0)!;
      expect(svg, startsWith('<svg xmlns="http://www.w3.org/2000/svg"'));
      expect(svg, contains('fill="#112233"'));
      expect('<path'.allMatches(svg).length, greaterThanOrEqualTo(2));
      final width =
          double.parse(RegExp(r'width="([\d.]+)"').firstMatch(svg)!.group(1)!);
      expect(width, lessThan(140), reason: 'cropped, not the pad size');
    });

    test('SVG background is optional', () {
      expect(c.toSvg(), isNot(contains('<rect')));
      expect(c.toSvg(background: Colors.white), contains('fill="#ffffff"'));
    });

    testWidgets('PNG has the right size', (tester) async {
      await tester.runAsync(() async {
        final image = await c.toImage(pixelRatio: 2, padding: 10);
        final bytes = await c.toPngBytes(pixelRatio: 2, padding: 10);
        expect(bytes!.sublist(1, 4), utf8.encode('PNG'));
        // export pads by the widest ink plus the padding on each side
        final area = c.export().bounds.inflate(c.style.width * 1.1 + 10);
        expect(image!.width, (area.width * 2).ceil());
        expect(image.height, (area.height * 2).ceil());
        image.dispose();
      });
    });
  });

  test('every ink style renders', () {
    for (final ink in InkStyle.values) {
      final c = SignatureController(
        initial: SignatureData([dash(10)]),
        style: SignatureStyle(ink: ink),
      );
      expect(c.toSvg(), contains('<path'), reason: ink.name);
    }
  });

  test('export can override the ink colour', () {
    final c = SignatureController(initial: SignatureData([dash(10)]));
    expect(
        c.toSvg(inkColor: const Color(0xFF000000)), contains('fill="#000000"'));
  });

  group('eraser', () {
    double inkLength(SignatureController c) =>
        c.strokes.fold(0.0, (sum, s) => sum + s.length);

    test('partial mode rubs out only around the point', () {
      final c = SignatureController(initial: SignatureData([dash(10)]));
      expect(c.eraseAt(const Offset(60, 10)), isTrue);
      expect(c.strokes, hasLength(2), reason: 'split in two');
      final gap = c.strokes.last.points.first.x - c.strokes.first.points.last.x;
      expect(gap, closeTo(c.eraserRadius * 2, 3));
      expect(inkLength(c), greaterThan(90));
    });

    test('a click where strokes cross keeps the rest of both', () {
      final c = SignatureController(
          initial: SignatureData([
        dash(10),
        SignatureStroke([
          for (var y = -40; y <= 60; y += 4)
            SignaturePoint(60, y.toDouble(), time: y.toDouble()),
        ]),
      ]));
      final before = inkLength(c);
      c.eraseAt(const Offset(60, 10));
      expect(c.strokes, hasLength(4));
      expect(inkLength(c), greaterThan(before * 0.75));
    });

    test('missing everything changes nothing', () {
      final c = SignatureController(initial: SignatureData([dash(10)]));
      expect(c.eraseAt(const Offset(500, 500)), isFalse);
      expect(c.canUndo, isFalse);
    });

    test('stroke mode removes only the strokes it touches', () {
      final c =
          SignatureController(initial: SignatureData([dash(10), dash(60)]))
            ..eraserMode = EraserMode.stroke;
      expect(c.eraseAt(const Offset(40, 62)), isTrue);
      expect(c.strokes.single.points.first.y, 10);
    });

    test('a drag is one undo step and shows live', () {
      final c = SignatureController(initial: SignatureData([dash(10)]));
      var notified = 0;
      c.addListener(() => notified++);
      c.beginErase(const Offset(20, 10));
      c.eraseAt(const Offset(40, 10));
      c.eraseAt(const Offset(60, 10));
      expect(notified, greaterThan(0), reason: 'pad updates mid drag');
      expect(c.eraserPosition, const Offset(60, 10));
      c.endErase();
      expect(c.eraserPosition, isNull);
      expect(inkLength(c), lessThan(80));
      c.undo();
      expect(c.strokes.single.length, closeTo(120, 1));
      expect(c.canUndo, isFalse, reason: 'only one step was added');
    });

    test('a cancelled drag puts everything back', () {
      final c = SignatureController(initial: SignatureData([dash(10)]));
      c.beginErase(const Offset(60, 10));
      expect(c.strokes, hasLength(2));
      c.cancelErase();
      expect(c.strokes.single.length, closeTo(120, 1));
      expect(c.canUndo, isFalse);
    });
  });
}
