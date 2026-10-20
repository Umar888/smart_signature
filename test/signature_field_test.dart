import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_signature/smart_signature.dart';

Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(16), child: child),
      ),
    );

Future<void> sign(WidgetTester tester) async {
  final pad = tester.getRect(find.byType(SignaturePad));
  await tester.dragFrom(
    pad.centerLeft + const Offset(30, 0),
    const Offset(200, 20),
  );
  await tester.pump();
}

Finder tool(SignatureTool t) => find.byKey(ValueKey(t));

void main() {
  testWidgets('toolbar sits on top of the pad', (tester) async {
    await tester.pumpWidget(host(const SignatureField()));
    final toolbar = tester.getRect(tool(SignatureTool.enhance));
    final pad = tester.getRect(find.byType(SignaturePad));
    expect(toolbar.bottom, lessThanOrEqualTo(pad.top));
    expect(find.text('Sign here'), findsOneWidget);
  });

  testWidgets('works without a controller', (tester) async {
    SignatureController? last;
    await tester.pumpWidget(host(SignatureField(onChanged: (c) => last = c)));
    await sign(tester);
    expect(last!.strokes, hasLength(1));
  });

  testWidgets('enhance toggles the view', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SignatureField(controller: c)));
    expect(c.enhance, isTrue);
    await tester.tap(tool(SignatureTool.enhance));
    await tester.pump();
    expect(c.enhance, isFalse);
  });

  testWidgets('ink, colour and width menus change the style', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SignatureField(controller: c)));

    await tester.tap(tool(SignatureTool.ink));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fountain'));
    await tester.pumpAndSettle();
    expect(c.style.ink, InkStyle.fountain);

    await tester.tap(tool(SignatureTool.width));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bold'));
    await tester.pumpAndSettle();
    expect(c.style.width, 4);

    await tester.tap(tool(SignatureTool.color));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('#7a1f2b'));
    await tester.pumpAndSettle();
    expect(c.style.color, SignatureField.lightInks[3]);
  });

  testWidgets('undo, redo and clear follow the history', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SignatureField(controller: c)));
    bool active(SignatureTool t) =>
        tester
            .widget<InkWell>(
                find.descendant(of: tool(t), matching: find.byType(InkWell)))
            .onTap !=
        null;

    expect(active(SignatureTool.undo), isFalse);
    expect(active(SignatureTool.clear), isFalse);

    await sign(tester);
    expect(active(SignatureTool.undo), isTrue);

    await tester.tap(tool(SignatureTool.clear));
    await tester.pump();
    expect(c.isEmpty, isTrue);
    await tester.tap(tool(SignatureTool.undo));
    await tester.pump();
    expect(c.strokes, hasLength(1));
    await tester.tap(tool(SignatureTool.redo));
    await tester.pump();
    expect(c.isEmpty, isTrue);
  });

  testWidgets('only the requested tools are shown', (tester) async {
    await tester.pumpWidget(host(const SignatureField(
      tools: {SignatureTool.color, SignatureTool.clear},
    )));
    expect(tool(SignatureTool.color), findsOneWidget);
    expect(tool(SignatureTool.clear), findsOneWidget);
    expect(tool(SignatureTool.enhance), findsNothing);
    expect(tool(SignatureTool.undo), findsNothing);
  });

  testWidgets('no tools hides the toolbar', (tester) async {
    await tester.pumpWidget(host(const SignatureField(tools: {})));
    expect(tool(SignatureTool.undo), findsNothing);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('labels are localisable', (tester) async {
    await tester.pumpWidget(host(const SignatureField(
      labels:
          SignatureFieldLabels(hint: 'Hier unterschreiben', undo: 'Rückgängig'),
    )));
    expect(find.text('Hier unterschreiben'), findsOneWidget);
    expect(find.byTooltip('Rückgängig'), findsOneWidget);
  });

  testWidgets('disabled field ignores the pad and the toolbar', (tester) async {
    final c = SignatureController();
    await tester
        .pumpWidget(host(SignatureField(controller: c, enabled: false)));
    await sign(tester);
    await tester.tap(tool(SignatureTool.enhance));
    await tester.pump();
    expect(c.isEmpty, isTrue);
    expect(c.enhance, isTrue);
  });

  testWidgets('fits a narrow phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(const SignatureField()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('swapping the controller rewires the field', (tester) async {
    final a = SignatureController();
    final b = SignatureController();
    await tester.pumpWidget(host(SignatureField(controller: a)));
    await tester.pumpWidget(host(SignatureField(controller: b)));
    await sign(tester);
    expect(a.isEmpty, isTrue);
    expect(b.strokes, hasLength(1));
  });

  testWidgets('eraser click rubs out a bit, not the signature', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SignatureField(controller: c)));
    await sign(tester);
    final before = c.strokes.single.length;

    await tester.tap(tool(SignatureTool.eraser));
    await tester.pump();
    expect(c.erasing, isTrue);
    final pad = tester.getRect(find.byType(SignaturePad));
    await tester.tapAt(pad.centerLeft + const Offset(130, 13));
    await tester.pump();
    final after = c.strokes.fold(0.0, (sum, s) => sum + s.length);
    expect(c.strokes, hasLength(2));
    expect(after, greaterThan(before * 0.8));

    // one undo brings it all back, and picking a pen leaves eraser mode
    await tester.tap(tool(SignatureTool.undo));
    await tester.tap(tool(SignatureTool.ink));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marker'));
    await tester.pumpAndSettle();
    expect(c.strokes.single.length, closeTo(before, 0.01));
    expect(c.erasing, isFalse);
  });

  testWidgets('eraser panel switches to whole strokes', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SignatureField(controller: c)));
    await tester.tap(find.byTooltip('Eraser settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whole stroke'));
    await tester.pumpAndSettle();
    expect(c.eraserMode, EraserMode.stroke);
    expect(c.erasing, isTrue);
  });

  testWidgets('custom colour from the hex field', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SignatureField(controller: c)));
    await tester.tap(tool(SignatureTool.color));
    await tester.pumpAndSettle();
    await tester.tap(find.text('More colours…'));
    await tester.pumpAndSettle();
    expect(find.text('Custom colour'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '12AB34');
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(c.style.color, const Color(0xFF12AB34));

    // it shows up under recent colours next time
    await tester.tap(tool(SignatureTool.color));
    await tester.pumpAndSettle();
    expect(find.text('Recent colours'), findsOneWidget);
  });

  testWidgets('enhance panel changes the enhancer options', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(host(SignatureField(controller: c)));
    await tester.tap(find.byTooltip('Enhance settings'));
    await tester.pumpAndSettle();
    expect(find.text('Smart enhance'), findsOneWidget);

    await tester.tap(find.text('Straighten on export'));
    await tester.pumpAndSettle();
    final options = (c.enhancer as SmartEnhancer).options;
    expect(options.straighten, isFalse);
    expect(options.removeHooks, isTrue);
  });

  testWidgets('dark theme gets a dark pad and light ink', (tester) async {
    final c = SignatureController();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: SignatureField(controller: c)),
    ));
    await tester.pump();
    expect(c.style.color, SignatureField.darkInks.first);
    final paper = tester.widget<ColoredBox>(find
        .descendant(
            of: find.byType(SignaturePad), matching: find.byType(ColoredBox))
        .first);
    expect(paper.color.computeLuminance(), lessThan(0.2));
  });

  testWidgets('switching back to light restores the pen', (tester) async {
    final c = SignatureController();
    Widget app(Brightness b) => MaterialApp(
          theme: ThemeData(brightness: b),
          home: Scaffold(body: SignatureField(controller: c)),
        );
    await tester.pumpWidget(app(Brightness.dark));
    await tester.pump();
    await tester.pumpWidget(app(Brightness.light));
    await tester.pumpAndSettle();
    expect(c.style.color, SignatureField.lightInks.first);
  });
}
