import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:smart_signature/smart_signature.dart';

import 'sample_signature.dart';

void main() => runApp(const DemoApp());

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'smart_signature',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF3F51B5)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF3F51B5),
        brightness: Brightness.dark,
      ),
      home: const SignatureDemo(),
    );
  }
}

/// A typical "sign to confirm" screen: the field plus a save button.
class SignatureDemo extends StatefulWidget {
  const SignatureDemo({super.key});

  @override
  State<SignatureDemo> createState() => _SignatureDemoState();
}

class _SignatureDemoState extends State<SignatureDemo> {
  final _signature = SignatureController();
  final _fieldKey = GlobalKey();

  static const _padHeight = 220.0;

  @override
  void dispose() {
    _signature.dispose();
    super.dispose();
  }

  void _loadSample() {
    final box = _fieldKey.currentContext!.findRenderObject()! as RenderBox;
    final size = Size(box.size.width, _padHeight);
    _signature.load(SignatureData(sampleStrokes(size)));
  }

  Future<void> _save() async {
    final png = await _signature.toPngBytes();
    if (png == null || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SavedSheet(png: png),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery receipt'),
        actions: [
          TextButton(onPressed: _loadSample, child: const Text('Try sample')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Order #4821', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            '3 items delivered to Umar Ghaffar, Lahore.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          Text('Customer signature', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SignatureField(
            key: _fieldKey,
            controller: _signature,
            height: _padHeight,
          ),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: _signature,
            builder: (context, _) => FilledButton(
              onPressed: _signature.isEmpty ? null : _save,
              child: const Text('Save signature'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SavedSheet extends StatelessWidget {
  const _SavedSheet({required this.png});

  final Uint8List png;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Saved signature', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Straightened, cropped to the ink, transparent PNG '
            '(${(png.length / 1024).toStringAsFixed(1)} KB).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? theme.colorScheme.surfaceContainerHigh
                  : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Image.memory(png, height: 140),
            ),
          ),
        ],
      ),
    );
  }
}
