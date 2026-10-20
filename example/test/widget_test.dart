import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_signature/smart_signature.dart';
import 'package:smart_signature_example/main.dart';

void main() {
  testWidgets('sample loads, enhances and saves', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const DemoApp());
    final save = find.widgetWithText(FilledButton, 'Save signature');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);

    await tester.tap(find.text('Try sample'));
    await tester.pump();
    expect(find.text('Sign here'), findsNothing);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    final field = tester.widget<SignatureField>(find.byType(SignatureField));
    final c = field.controller!;
    // the stray tap is in the raw strokes but dropped once enhanced
    expect(c.strokes, hasLength(4));
    expect(c.displayStrokes, hasLength(3));
  });
}
