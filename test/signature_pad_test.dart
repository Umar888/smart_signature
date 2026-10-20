import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_signature/smart_signature.dart';

Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('drawing adds a stroke', (tester) async {
    final c = SignatureController();
    var ended = 0;
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 200,
      child: SignaturePad(controller: c, onStrokeEnd: () => ended++),
    )));
    expect(find.text('Sign here'), findsOneWidget);

    final gesture = await tester.startGesture(const Offset(50, 100));
    for (var x = 60.0; x <= 300; x += 10) {
      await gesture.moveTo(Offset(x, 100 + (x % 30) - 15));
    }
    await gesture.up();
    await tester.pump();

    expect(c.strokes, hasLength(1));
    expect(c.strokes.single.points.length, greaterThan(20));
    expect(ended, 1);
    expect(find.text('Sign here'), findsNothing);
  });

  testWidgets('signing inside a scroll view does not scroll it',
      (tester) async {
    final c = SignatureController();
    final scroll = ScrollController();
    await tester.pumpWidget(host(ListView(
      controller: scroll,
      children: [
        SizedBox(height: 300, child: SignaturePad(controller: c)),
        const SizedBox(height: 2000),
      ],
    )));

    // a mostly vertical stroke would normally start a scroll
    await tester.dragFrom(const Offset(200, 50), const Offset(10, 200));
    await tester.pump();

    expect(scroll.offset, 0);
    expect(c.strokes, hasLength(1));
  });

  testWidgets('a second finger is ignored', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 200,
      child: SignaturePad(controller: c),
    )));
    final first = await tester.startGesture(const Offset(50, 100));
    final second = await tester.startGesture(const Offset(300, 50), pointer: 9);
    await first.moveTo(const Offset(150, 100));
    await second.moveTo(const Offset(300, 150));
    await second.up();
    await first.up();
    await tester.pump();
    expect(c.strokes, hasLength(1));
    expect(c.strokes.single.points.every((p) => p.y == 100), isTrue);
  });

  testWidgets('disabled pad ignores input', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 200,
      child: SignaturePad(controller: c, enabled: false),
    )));
    await tester.dragFrom(const Offset(50, 100), const Offset(200, 0));
    expect(c.isEmpty, isTrue);
  });

  testWidgets('repaints after undo', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 200,
      child: SignaturePad(controller: c),
    )));
    await tester.dragFrom(const Offset(50, 100), const Offset(200, 0));
    await tester.pump();
    expect(find.text('Sign here'), findsNothing);
    c.undo();
    await tester.pump();
    expect(find.text('Sign here'), findsOneWidget);
  });
}
