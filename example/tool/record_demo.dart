// Plays a scripted walkthrough of the demo for recording the README GIF.
//   flutter run -t tool/record_demo.dart
// The signature is signed through the normal gesture pipeline at a human
// pace, so what you see is exactly what a finger would produce.
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:smart_signature/smart_signature.dart';
import 'package:smart_signature_example/main.dart';
import 'package:smart_signature_example/sample_signature.dart';

void main() {
  runApp(const DemoApp());
  unawaited(_play());
}

final _clock = Stopwatch()..start();
int _pointer = 100;
const _frame = 8;

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void _send(PointerEvent event) =>
    GestureBinding.instance.handlePointerEvent(event);

Duration get _now => _clock.elapsed;

RenderBox _box(bool Function(Widget) test) {
  RenderBox? found;
  void visit(Element element) {
    if (found != null) return;
    if (test(element.widget) && element.renderObject is RenderBox) {
      found = element.renderObject! as RenderBox;
      return;
    }
    element.visitChildElements(visit);
  }

  WidgetsBinding.instance.rootElement!.visitChildElements(visit);
  return found!;
}

Offset _center(RenderBox box) =>
    box.localToGlobal(box.size.center(Offset.zero));

Offset _text(String label) =>
    _center(_box((w) => w is Text && w.data == label));

Future<void> _tapAt(Offset at) async {
  final p = _pointer++;
  _send(PointerDownEvent(pointer: p, position: at, timeStamp: _now));
  await _wait(70);
  _send(PointerUpEvent(pointer: p, position: at, timeStamp: _now));
}

/// Signs [strokes] (pad coordinates, ms timestamps) onto the pad, sending
/// whatever points are due every frame like a real touch screen would.
Future<void> _sign(List<SignatureStroke> strokes, RenderBox pad) async {
  final origin = pad.localToGlobal(Offset.zero);
  final start = _clock.elapsedMilliseconds;
  for (final stroke in strokes) {
    final p = _pointer++;
    final points = stroke.points;
    Offset at(int i) => origin + points[i].offset;
    while (_clock.elapsedMilliseconds - start < points.first.time) {
      await _wait(_frame);
    }
    _send(PointerDownEvent(pointer: p, position: at(0), timeStamp: _now));
    var i = 1;
    while (i < points.length) {
      while (i < points.length &&
          points[i].time <= _clock.elapsedMilliseconds - start) {
        _send(PointerMoveEvent(
          pointer: p,
          position: at(i),
          delta: at(i) - at(i - 1),
          timeStamp: _now,
        ));
        i++;
      }
      await _wait(_frame);
    }
    _send(PointerUpEvent(
      pointer: p,
      position: at(points.length - 1),
      timeStamp: _now,
    ));
  }
}

Offset _tool(String tooltip) =>
    _center(_box((w) => w is Tooltip && w.message == tooltip));

Offset _swatch(String hex) =>
    _center(_box((w) => w is Semantics && w.properties.label == hex));

/// A slow, curvy rub across [from] to [to] with the eraser.
Future<void> _rub(Offset from, Offset to, int ms) async {
  final p = _pointer++;
  var last = from;
  _send(PointerDownEvent(pointer: p, position: from, timeStamp: _now));
  final steps = ms ~/ 16;
  for (var i = 1; i <= steps; i++) {
    final next = Offset.lerp(from, to, i / steps)!;
    _send(PointerMoveEvent(
      pointer: p,
      position: next,
      delta: next - last,
      timeStamp: _now,
    ));
    last = next;
    await _wait(16);
  }
  _send(PointerUpEvent(pointer: p, position: to, timeStamp: _now));
}

Future<void> _play() async {
  // time for the screen recording to start
  await _wait(4500);
  final pad = _box((w) => w is SignaturePad);

  // sign with enhancement off first, so the shaky input is visible
  await _tapAt(_tool('Enhance'));
  await _wait(700);
  await _sign(sampleStrokes(pad.size), pad);
  await _wait(1400);

  await _tapAt(_tool('Enhance'));
  await _wait(1800);
  await _tapAt(_tool('Enhance'));
  await _wait(1000);
  await _tapAt(_tool('Enhance'));
  await _wait(1300);

  await _tapAt(_tool('Ink'));
  await _wait(1200);
  await _tapAt(_text('Fountain'));
  await _wait(1100);

  await _tapAt(_tool('Colour'));
  await _wait(1300);
  await _tapAt(_swatch('#7a1f2b'));
  await _wait(1000);

  await _tapAt(_tool('Width'));
  await _wait(1100);
  await _tapAt(_text('Bold'));
  await _wait(900);
  await _tapAt(_tool('Width'));
  await _wait(1000);

  // rub out a bit, then think better of it
  await _tapAt(_tool('Eraser'));
  await _wait(700);
  final origin = pad.localToGlobal(Offset.zero);
  final size = pad.size;
  await _rub(
    origin + Offset(size.width * 0.42, size.height * 0.35),
    origin + Offset(size.width * 0.5, size.height * 0.75),
    700,
  );
  await _wait(900);
  await _tapAt(_tool('Undo'));
  await _wait(1000);

  await _tapAt(_text('Save signature'));
  await _wait(3500);
  debugPrint('DEMO_SHEET');

  // the simulator recorder drops its last few frames, so keep the screen
  // changing for a while; this part is trimmed from the GIF
  await _tapAt(const Offset(40, 120));
  for (var i = 0; i < 8; i++) {
    await _wait(500);
    await _tapAt(_tool('Enhance'));
  }
  debugPrint('DEMO_DONE');
}
