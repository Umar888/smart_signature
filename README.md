# smart_signature

<p align="center">
  <img src="https://raw.githubusercontent.com/Umar888/smart_signature/main/doc/demo.gif" alt="smart_signature demo" width="320">
</p>

A Flutter signature field that cleans up what you draw. Shaky lines come out
smooth, the little hooks where the pen lands and lifts are trimmed, stray taps
disappear and a tilted signature is levelled on export. Ink gets a real pen
feel: thinner when you move fast, thicker when you slow down, tapered ends.

Everything runs on the device in plain Dart. It's instant, works offline and
the signature never leaves the phone.

| As drawn | Enhanced |
| --- | --- |
| ![Raw signature](https://raw.githubusercontent.com/Umar888/smart_signature/main/doc/before.png) | ![Enhanced signature](https://raw.githubusercontent.com/Umar888/smart_signature/main/doc/after.png) |

## Features

- `SignatureField`: drop-in widget with a formatting toolbar on top, like a rich text box
- Smart enhance: removes jitter, pen hooks and stray marks, refits strokes as smooth curves, straightens on export
- Ballpoint, fountain (calligraphy nib) and marker inks, each previewed in the picker
- Word style colour palette: ink colours, theme grid with tints and shades, standard colours, recent colours and a full custom picker with hex input
- Stroke width presets plus a fine slider with a live preview
- Eraser that rubs out just what you touch, or whole strokes
- Undo and redo, including clear and every erase
- Follows light and dark mode, and swaps the ink so the signature stays visible
- Export to PNG (transparent or with a background), SVG or JSON, cropped to the ink
- Stylus pressure when the device reports it
- Claims the gesture right away, so signing inside a scroll view doesn't scroll it
- Every label can be replaced for localisation
- No dependencies besides Flutter

## Getting started

```yaml
dependencies:
  smart_signature: ^0.1.0
```

```dart
import 'package:smart_signature/smart_signature.dart';
```

## Usage

### The field

```dart
final signature = SignatureController();

SignatureField(controller: signature, height: 220)
```

Read the result whenever you need it, for example from your form's submit
button:

```dart
final Uint8List? png = await signature.toPngBytes();
final String? svg = signature.toSvg();
final Map<String, Object> json = signature.toData().toJson();
```

Exports are cropped to the ink, enhanced and straightened. PNGs are
transparent unless you pass a `background`. If people sign in dark mode but
the signature goes on a white document, force the ink colour:

```dart
await signature.toPngBytes(
  background: Colors.white,
  inkColor: const Color(0xFF1C2A5A),
);
```

Load a saved signature back with
`signature.load(SignatureData.fromJson(json))`.

### Choosing the tools

```dart
SignatureField(
  controller: signature,
  tools: {SignatureTool.color, SignatureTool.undo, SignatureTool.clear},
)
```

Pass an empty set to hide the toolbar. You can also set your own ink colours
(`colors`), width presets (`widths`) and the pad colour (`padColor`).

### Text and localisation

The "Sign here" hint and every tooltip and panel label live in
`SignatureFieldLabels`:

```dart
SignatureField(
  labels: const SignatureFieldLabels(
    hint: 'Firme aquí',
    undo: 'Deshacer',
    clear: 'Borrar',
  ),
)
```

An empty `hint` hides it.

### Just the pad

Building your own UI? `SignaturePad` is the bare signing surface, and the
controller holds everything else:

```dart
SignaturePad(controller: signature)

signature.style = const SignatureStyle(
  color: Color(0xFF1C2A5A),
  width: 2.6,
  ink: InkStyle.fountain,
);
signature.enhance = false; // show exactly what was drawn
signature.erasing = true;
signature.undo();
```

### Tuning or replacing the enhancement

```dart
signature.enhancer = const SmartEnhancer(
  options: EnhanceOptions(
    smoothing: 0.7,        // 0 keeps the lines as drawn, 1 irons out every wobble
    removeHooks: true,
    removeStrayMarks: true,
    straighten: true,      // on export only
    maxTilt: 20,           // steeper slants are treated as intentional
  ),
);
```

`SmartEnhancer` is one implementation of `SignatureEnhancer`. Implement
`enhance` (and optionally `finalize`) to plug in your own, for example an ML
model.

## How the enhancement works

Each stroke is resampled to an even spacing, then:

1. **Hooks**: the first and last 14px are checked for a sharp turn, the tick a
   pen leaves when it lands or lifts, and trimmed there.
2. **Jitter**: a Gaussian blur along the stroke removes the pixel level shake,
   with the window shrinking at the ends so strokes keep their reach.
3. **Refit**: the line is simplified (Ramer-Douglas-Peucker) and redrawn as a
   centripetal Catmull-Rom spline, which flattens the slower wobble a blur
   leaves behind without adding loops.
4. **Stray marks**: tiny strokes well outside the signature are dropped. Dots
   inside it, like on an i, stay.
5. **Straighten**: on export, the main axis of all the ink is measured and a
   tilt between 0.5° and `maxTilt` is rotated level.

Steps 1 to 4 run live after every stroke. Straightening only runs on export,
so ink never moves under your finger while you're still signing.

Ink width is computed per point from speed (or stylus pressure), the
direction for the fountain nib, and a taper at both ends. Each stroke is then
filled as a smooth outline with round caps, the same shape for the screen, PNG
and SVG.

## Example

The [example](example) app is a delivery receipt screen with the field and a
save button. "Try sample" loads a deliberately shaky, tilted signature so you
can see what Enhance does.

## Contributing

Issues and pull requests are welcome on
[GitHub](https://github.com/Umar888/smart_signature).

## Author

Made by [Umar Ghaffar](https://github.com/Umar888). If this package saves you
some time, a like on pub.dev or a star on GitHub is much appreciated.

Also by me:
[liquid_glass_navigation](https://pub.dev/packages/liquid_glass_navigation), iOS 26 style Liquid Glass navigation for Flutter, and
[scroll_edge_blur](https://pub.dev/packages/scroll_edge_blur), iOS style progressive edge blur for scroll views, toolbars and headers.
