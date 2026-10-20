import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'geometry.dart';
import 'signature_controller.dart';
import 'signature_data.dart';
import 'signature_style.dart';
import 'stroke_renderer.dart';

/// A surface to sign on. Strokes go into [controller], which also enhances
/// and exports them.
///
/// The pad claims the gesture as soon as the pen lands, so signing inside a
/// scrollable page doesn't scroll it.
class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.controller,
    this.backgroundColor,
    this.showBaseline = true,
    this.baselineColor,
    this.hint = 'Sign here',
    this.hintStyle,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.enabled = true,
    this.onStrokeEnd,
  });

  final SignatureController controller;

  /// Paper colour. Defaults to white in light mode and a dark surface in
  /// dark mode.
  final Color? backgroundColor;

  /// A line to sign on, about two thirds down.
  final bool showBaseline;
  final Color? baselineColor;

  /// Shown above the baseline while the pad is empty. Null hides it.
  final String? hint;
  final TextStyle? hintStyle;

  final BorderRadius borderRadius;

  /// When false the pad ignores input but still shows the signature.
  final bool enabled;

  /// Called after each stroke is added.
  final VoidCallback? onStrokeEnd;

  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  static const double _baselineFraction = 0.68;
  static const double _inset = 24;

  var _erasing = false;

  SignaturePoint _point(PointerEvent e) => SignaturePoint(
        e.localPosition.dx,
        e.localPosition.dy,
        time: e.timeStamp.inMicroseconds / 1000,
        // mice and touch screens report 1 or 0, the renderer ignores flat pressure
        pressure: e.pressureMax > e.pressureMin
            ? ((e.pressure - e.pressureMin) / (e.pressureMax - e.pressureMin))
                .clamp(0.0, 1.0)
            : 0.5,
      );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final paper = widget.backgroundColor ??
        (dark ? scheme.surfaceContainerHigh : const Color(0xFFFFFFFF));
    final baseline = widget.baselineColor ?? scheme.outlineVariant;
    Widget pad = Stack(
      fit: StackFit.expand,
      children: [
        if (widget.showBaseline)
          CustomPaint(
            painter: _BaselinePainter(baseline, _baselineFraction),
          ),
        if (widget.hint case final hint?)
          ListenableBuilder(
            listenable: Listenable.merge([controller, controller.activeStroke]),
            builder: (context, _) {
              final empty =
                  controller.isEmpty && controller.activePoints == null;
              return LayoutBuilder(
                builder: (context, box) => Stack(
                  children: [
                    if (empty)
                      Positioned(
                        left: _inset,
                        right: _inset,
                        bottom: box.maxHeight * (1 - _baselineFraction) + 6,
                        child: IgnorePointer(
                          child: Text(
                            hint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: widget.hintStyle ??
                                TextStyle(
                                  color: scheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                  fontSize: 15,
                                ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        // finished strokes repaint only when the signature changes
        RepaintBoundary(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => CustomPaint(
              painter: _StrokesPainter(controller.displayStrokes,
                  controller.style, controller.enhance),
            ),
          ),
        ),
        CustomPaint(
            painter: _ActivePainter(controller, scheme.onSurfaceVariant)),
      ],
    );
    if (widget.enabled) {
      pad = RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _SignatureRecognizer:
              GestureRecognizerFactoryWithHandlers<_SignatureRecognizer>(
            () => _SignatureRecognizer(debugOwner: this),
            (r) => r
              ..onStart = (e) {
                // the mode is fixed for the whole gesture
                _erasing = controller.erasing;
                _erasing
                    ? controller.beginErase(e.localPosition)
                    : controller.beginStroke(_point(e));
              }
              ..onUpdate = ((e) => _erasing
                  ? controller.eraseAt(e.localPosition)
                  : controller.addPoint(_point(e)))
              ..onEnd = () {
                if (_erasing) {
                  controller.endErase();
                  return;
                }
                controller.endStroke();
                widget.onStrokeEnd?.call();
              }
              ..onCancel = () => _erasing
                  ? controller.cancelErase()
                  : controller.cancelStroke(),
          ),
        },
        child: pad,
      );
    }
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: ColoredBox(color: paper, child: pad),
    );
  }
}

/// Accepts the pointer straight away so no scroll view can steal the stroke,
/// and follows one pointer at a time.
class _SignatureRecognizer extends OneSequenceGestureRecognizer {
  _SignatureRecognizer({super.debugOwner});

  ValueChanged<PointerEvent>? onStart;
  ValueChanged<PointerEvent>? onUpdate;
  VoidCallback? onEnd;
  VoidCallback? onCancel;
  int? _pointer;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_pointer != null) return;
    super.addAllowedPointer(event);
    _pointer = event.pointer;
    resolve(GestureDisposition.accepted);
    onStart?.call(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      onUpdate?.call(event);
    } else if (event is PointerUpEvent) {
      onUpdate?.call(event);
      _finish(event.pointer);
      onEnd?.call();
    } else if (event is PointerCancelEvent) {
      _finish(event.pointer);
      onCancel?.call();
    }
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer != _pointer) return;
    _finish(pointer);
    onCancel?.call();
  }

  void _finish(int pointer) {
    _pointer = null;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'signature';
}

class _StrokesPainter extends CustomPainter {
  const _StrokesPainter(this.strokes, this.style, this.ink);

  final List<SignatureStroke> strokes;
  final SignatureStyle style;
  final bool ink;

  @override
  void paint(Canvas canvas, Size size) =>
      paintStrokes(canvas, strokes, style, ink: ink);

  @override
  bool shouldRepaint(_StrokesPainter old) =>
      old.strokes != strokes || old.style != style || old.ink != ink;
}

/// The stroke under the pen, lightly smoothed so it already looks like ink.
class _ActivePainter extends CustomPainter {
  _ActivePainter(this.controller, this.ringColor)
      : super(repaint: controller.activeStroke);

  final SignatureController controller;

  /// Outline of the eraser while rubbing out.
  final Color ringColor;

  static const double _spacing = 1.5;
  static const double _sigma = 1;

  @override
  void paint(Canvas canvas, Size size) {
    final eraser = controller.eraserPosition;
    if (eraser != null) {
      final r = controller.eraserRadius;
      canvas
        ..drawCircle(
            eraser, r, Paint()..color = ringColor.withValues(alpha: 0.12))
        ..drawCircle(
          eraser,
          r,
          Paint()
            ..color = ringColor.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
    }
    final points = controller.activePoints;
    if (points == null) return;
    final ink = controller.enhance;
    final live =
        ink ? gaussianSmooth(resample(points, _spacing), _sigma) : points;
    paintStrokes(canvas, [SignatureStroke(live)], controller.style, ink: ink);
  }

  @override
  bool shouldRepaint(_ActivePainter old) =>
      old.controller != controller || old.ringColor != ringColor;
}

class _BaselinePainter extends CustomPainter {
  const _BaselinePainter(this.color, this.fraction);

  final Color color;
  final double fraction;

  static const double _inset = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * fraction;
    canvas.drawLine(
      Offset(_inset, y),
      Offset(size.width - _inset, y),
      Paint()
        ..color = color
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_BaselinePainter old) =>
      old.color != color || old.fraction != fraction;
}
