import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'signature_controller.dart';
import 'signature_data.dart';
import 'signature_field.dart';
import 'signature_style.dart';
import 'smart_enhancer.dart';
import 'stroke_renderer.dart';

/// A gentle S curve, slow at the ends and fast in the middle, so previews
/// show the ink's taper and speed response.
SignatureStroke _swoosh(Size size) {
  const samples = 48;
  final points = <SignaturePoint>[];
  var time = 0.0;
  Offset? previous;
  for (var i = 0; i <= samples; i++) {
    final t = i / samples;
    final p = Offset(
      6 + t * (size.width - 12),
      size.height / 2 - math.sin(t * 2 * math.pi) * size.height * 0.26,
    );
    if (previous != null) {
      time += (p - previous).distance / (0.3 + 2.2 * math.sin(math.pi * t));
    }
    previous = p;
    points.add(SignaturePoint(p.dx, p.dy, time: time));
  }
  return SignatureStroke(points);
}

/// Live sample of [style], drawn by the same renderer as the pad.
class InkPreview extends StatelessWidget {
  const InkPreview({super.key, required this.style, required this.size});

  final SignatureStyle style;
  final Size size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: size, painter: _PreviewPainter(style));
}

class _PreviewPainter extends CustomPainter {
  const _PreviewPainter(this.style);

  final SignatureStyle style;

  @override
  void paint(Canvas canvas, Size size) =>
      paintStrokes(canvas, [_swoosh(size)], style, ink: true);

  @override
  bool shouldRepaint(_PreviewPainter old) => old.style != style;
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Selectable card with a rounded, tinted background when chosen.
class _Choice extends StatelessWidget {
  const _Choice(
      {required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: selected ? scheme.secondaryContainer : null,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected
                      ? scheme.secondary.withValues(alpha: 0.4)
                      : Colors.transparent),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Pick the pen: each option shows a stroke in that ink.
class InkPanel extends StatelessWidget {
  const InkPanel(
      {super.key,
      required this.style,
      required this.labels,
      required this.onSelected});

  final SignatureStyle style;
  final SignatureFieldLabels labels;
  final ValueChanged<InkStyle> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 268,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelTitle(labels.ink),
            for (final ink in InkStyle.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: _Choice(
                  selected: style.ink == ink,
                  onTap: () => onSelected(ink),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                    child: Row(
                      children: [
                        InkPreview(
                          style: style.copyWith(
                              ink: ink, width: math.max(style.width, 2.4)),
                          size: const Size(76, 34),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(labels.inkName(ink),
                                  style: theme.textTheme.titleSmall),
                              Text(
                                labels.inkDescription(ink),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (style.ink == ink)
                          Icon(Icons.check_circle,
                              size: 18, color: theme.colorScheme.primary),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Stroke width: preset cards plus a fine slider, previewed live.
class WidthPanel extends StatelessWidget {
  const WidthPanel({
    super.key,
    required this.style,
    required this.widths,
    required this.labels,
    required this.onChanged,
  });

  final SignatureStyle style;
  final List<SignatureWidth> widths;
  final SignatureFieldLabels labels;
  final ValueChanged<double> onChanged;

  static const double minWidth = 0.8;
  static const double maxWidth = 8;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: 268,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelTitle(labels.width),
            Row(
              children: [
                for (var i = 0; i < widths.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _Choice(
                      selected: style.width == widths[i].width,
                      onTap: () => onChanged(widths[i].width),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Column(
                          children: [
                            SizedBox(
                              height: 14,
                              child: Center(
                                child: Container(
                                  width: 36,
                                  height: widths[i].width,
                                  decoration: BoxDecoration(
                                    color: style.color,
                                    borderRadius:
                                        BorderRadius.circular(widths[i].width),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(widths[i].label,
                                style: theme.textTheme.labelMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: InkPreview(style: style, size: const Size(220, 36)),
            ),
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child:
                      Text(labels.custom, style: theme.textTheme.labelMedium),
                ),
                Expanded(
                  child: Slider(
                    value: style.width.clamp(minWidth, maxWidth),
                    min: minWidth,
                    max: maxWidth,
                    onChanged: onChanged,
                  ),
                ),
                SizedBox(
                  width: 34,
                  child: Text(
                    style.width.toStringAsFixed(1),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Smart enhance settings: master switch, smoothing and the individual
/// clean-up steps.
class EnhancePanel extends StatelessWidget {
  const EnhancePanel({
    super.key,
    required this.enabled,
    required this.options,
    required this.labels,
    required this.onEnabled,
    required this.onOptions,
  });

  final bool enabled;

  /// Null when the app plugged in its own enhancer, then only the switch shows.
  final EnhanceOptions? options;
  final SignatureFieldLabels labels;
  final ValueChanged<bool> onEnabled;
  final ValueChanged<EnhanceOptions> onOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = options;
    return SizedBox(
      width: 280,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [scheme.primary, scheme.tertiary]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.auto_fix_high,
                      size: 18, color: scheme.onPrimary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(labels.enhanceTitle,
                          style: theme.textTheme.titleSmall),
                      Text(
                        labels.enhanceSubtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Switch(value: enabled, onChanged: onEnabled),
              ],
            ),
            if (o != null)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: enabled ? 1 : 0.45,
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 14),
                      Text(labels.smoothing, style: theme.textTheme.labelLarge),
                      Slider(
                        value: o.smoothing,
                        onChanged: (v) => onOptions(o.copyWith(smoothing: v)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          children: [
                            Text(labels.natural,
                                style: theme.textTheme.bodySmall),
                            const Spacer(),
                            Text(labels.smooth,
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      _Toggle(
                        icon: Icons.content_cut,
                        label: labels.removeHooks,
                        value: o.removeHooks,
                        onChanged: (v) => onOptions(o.copyWith(removeHooks: v)),
                      ),
                      _Toggle(
                        icon: Icons.cleaning_services_outlined,
                        label: labels.removeStrayMarks,
                        value: o.removeStrayMarks,
                        onChanged: (v) =>
                            onOptions(o.copyWith(removeStrayMarks: v)),
                      ),
                      _Toggle(
                        icon: Icons.straighten,
                        label: labels.straighten,
                        value: o.straighten,
                        onChanged: (v) => onOptions(o.copyWith(straighten: v)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle(
      {required this.icon,
      required this.label,
      required this.value,
      required this.onChanged});

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
            Transform.scale(
                scale: 0.8, child: Switch(value: value, onChanged: onChanged)),
          ],
        ),
      ),
    );
  }
}

/// Eraser mode: rub out part of a line, or whole strokes.
class EraserPanel extends StatelessWidget {
  const EraserPanel({
    super.key,
    required this.mode,
    required this.labels,
    required this.onSelected,
  });

  final EraserMode mode;
  final SignatureFieldLabels labels;
  final ValueChanged<EraserMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget option(EraserMode value, IconData icon, String title, String body) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: _Choice(
            selected: mode == value,
            onTap: () => onSelected(value),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 20, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.titleSmall),
                        Text(
                          body,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (mode == value)
                    Icon(Icons.check_circle, size: 18, color: scheme.primary),
                ],
              ),
            ),
          ),
        );

    return SizedBox(
      width: 268,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PanelTitle(labels.eraser),
            option(EraserMode.partial, Icons.blur_on, labels.eraserPartial,
                labels.eraserPartialDescription),
            option(EraserMode.stroke, Icons.gesture, labels.eraserStroke,
                labels.eraserStrokeDescription),
          ],
        ),
      ),
    );
  }
}
