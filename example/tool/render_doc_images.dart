// Renders the sample signature before and after enhancement for the README.
//   flutter test tool/render_doc_images.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_signature/smart_signature.dart';
import 'package:smart_signature_example/sample_signature.dart';

void main() {
  testWidgets('render', (tester) async {
    final data = SignatureData(sampleStrokes(const Size(390, 240)));
    Future<void> save(String name, SignatureController c) async {
      await tester.runAsync(() async {
        final png = await c.toPngBytes(
          pixelRatio: 3,
          padding: 20,
          background: Colors.white,
        );
        File('../doc/$name.png').writeAsBytesSync(png!);
      });
    }

    await save('before', SignatureController(initial: data, enhance: false));
    await save('after', SignatureController(initial: data));
  });
}
