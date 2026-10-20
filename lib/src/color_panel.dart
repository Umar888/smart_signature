import 'package:flutter/material.dart';

import 'signature_field.dart';

// Word's theme row and standard colours, so the palette feels familiar.
const _themeBase = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFE7E6E6),
  Color(0xFF44546A),
  Color(0xFF4472C4),
  Color(0xFFED7D31),
  Color(0xFFA5A5A5),
  Color(0xFFFFC000),
  Color(0xFF5B9BD5),
  Color(0xFF70AD47),
];

const _standard = [
  Color(0xFFC00000),
  Color(0xFFFF0000),
  Color(0xFFFFC000),
  Color(0xFFFFFF00),
  Color(0xFF92D050),
  Color(0xFF00B050),
  Color(0xFF00B0F0),
  Color(0xFF0070C0),
  Color(0xFF002060),
  Color(0xFF7030A0),
];

/// The five tints and shades Word shows under each theme colour.
List<Color> _variants(Color base) {
  final white = const Color(0xFFFFFFFF), black = const Color(0xFF000000);
  if (base == white) {
    return [
      for (final t in [0.05, 0.15, 0.25, 0.35, 0.5]) Color.lerp(base, black, t)!
    ];
  }
  if (base == black) {
    return [
      for (final t in [0.5, 0.35, 0.25, 0.15, 0.05])
        Color.lerp(white, base, 1 - t)!
    ];
  }
  return [
    for (final t in [0.8, 0.6, 0.4]) Color.lerp(base, white, t)!,
    for (final t in [0.25, 0.5]) Color.lerp(base, black, t)!,
  ];
}

/// The colour popover: ink colours, Word style theme grid, standard
/// colours, recent picks and a full custom picker.
class ColorPanel extends StatelessWidget {
  const ColorPanel({
    super.key,
    required this.inks,
    required this.recent,
    required this.selected,
    required this.labels,
    required this.onSelected,
    required this.onMore,
  });

  final List<Color> inks;
  final List<Color> recent;
  final Color selected;
  final SignatureFieldLabels labels;
  final ValueChanged<Color> onSelected;
  final VoidCallback onMore;

  static const double width = 280;
  static const double _swatch = 20;
  static const double _gap = 4.8;

  @override
  Widget build(BuildContext context) {
    Widget row(List<Color> colors,
            {double size = _swatch, bool round = false}) =>
        Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final c in colors)
              _Swatch(c,
                  size: size,
                  round: round,
                  selected: c == selected,
                  onTap: () => onSelected(c)),
          ],
        );

    final columns = [for (final base in _themeBase) _variants(base)];
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Title(labels.inkColors),
            row(inks, size: 30, round: true),
            const SizedBox(height: 14),
            _Title(labels.themeColors),
            row(_themeBase),
            const SizedBox(height: 6),
            // shades read top to bottom like in Word, so lay out by column
            Row(
              children: [
                for (var i = 0; i < columns.length; i++) ...[
                  if (i > 0) const SizedBox(width: _gap),
                  Column(
                    children: [
                      for (final c in columns[i])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 1),
                          child: _Swatch(c,
                              size: _swatch,
                              flat: true,
                              selected: c == selected,
                              onTap: () => onSelected(c)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            _Title(labels.standardColors),
            row(_standard),
            if (recent.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Title(labels.recentColors),
              row(recent),
            ],
            const SizedBox(height: 10),
            _MoreButton(label: labels.moreColors, onTap: onMore),
          ],
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(
    this.color, {
    required this.size,
    required this.selected,
    required this.onTap,
    this.round = false,
    this.flat = false,
  });

  final Color color;
  final double size;
  final bool selected;
  final bool round;

  /// Shade cells sit edge to edge like Word's grid.
  final bool flat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(round ? size : (flat ? 3 : 5));
    // light swatches need an outline to show on a light panel
    final edge =
        color.computeLuminance() > 0.8 || color.computeLuminance() < 0.02
            ? scheme.outlineVariant
            : color;
    return Semantics(
      button: true,
      selected: selected,
      label: '#${_hex(color)}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: size,
          height: size,
          padding: EdgeInsets.all(selected ? 2 : 0),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: radius,
              border: Border.all(color: edge, width: 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(colors: [
                  Color(0xFFFF0000),
                  Color(0xFFFFFF00),
                  Color(0xFF00FF00),
                  Color(0xFF00FFFF),
                  Color(0xFF0000FF),
                  Color(0xFFFF00FF),
                  Color(0xFFFF0000),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            Text(label, style: theme.textTheme.labelLarge),
            const Spacer(),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// Full colour picker: saturation/brightness square, hue strip and hex input.
Future<Color?> showCustomColorDialog(
    BuildContext context, Color initial, SignatureFieldLabels labels) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _CustomColorDialog(initial: initial, labels: labels),
  );
}

class _CustomColorDialog extends StatefulWidget {
  const _CustomColorDialog({required this.initial, required this.labels});

  final Color initial;
  final SignatureFieldLabels labels;

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final _hex = TextEditingController(text: _hexOf(widget.initial));

  static const double _width = 264;

  Color get _color => _hsv.toColor();

  void _set(HSVColor hsv) {
    setState(() => _hsv = hsv);
    _hex.text = _hexOf(hsv.toColor());
  }

  void _typed(String text) {
    final value = int.tryParse(text.replaceAll('#', ''), radix: 16);
    if (text.replaceAll('#', '').length != 6 || value == null) return;
    setState(() => _hsv = HSVColor.fromColor(Color(0xFF000000 | value)));
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels = widget.labels;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: SizedBox(
          width: _width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(labels.customColor, style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              _SaturationValue(hsv: _hsv, onChanged: _set),
              const SizedBox(height: 14),
              _HueStrip(hsv: _hsv, onChanged: _set),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Compare(before: widget.initial, after: _color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _hex,
                      onChanged: _typed,
                      maxLength: 7,
                      style: theme.textTheme.bodyLarge?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()]),
                      decoration: const InputDecoration(
                        prefixText: '# ',
                        counterText: '',
                        isDense: true,
                        border: OutlineInputBorder(
                            borderRadius:
                                BorderRadius.all(Radius.circular(12))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(labels.cancel)),
                  const SizedBox(width: 4),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, _color),
                      child: Text(labels.select)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaturationValue extends StatelessWidget {
  const _SaturationValue({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const double _height = 168;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, _height);
      void pick(Offset p) => onChanged(hsv
          .withSaturation((p.dx / size.width).clamp(0.0, 1.0))
          .withValue(1 - (p.dy / size.height).clamp(0.0, 1.0)));
      final thumb =
          Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
      return GestureDetector(
        onPanDown: (d) => pick(d.localPosition),
        onPanUpdate: (d) => pick(d.localPosition),
        child: SizedBox.fromSize(
          size: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFFFFFFFF),
                      HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
                    ]),
                  ),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xFF000000)],
                      ),
                    ),
                    child: SizedBox.expand(),
                  ),
                ),
              ),
              Positioned(
                  left: thumb.dx - 11,
                  top: thumb.dy - 11,
                  child: _Thumb(hsv.toColor())),
            ],
          ),
        ),
      );
    });
  }
}

class _HueStrip extends StatelessWidget {
  const _HueStrip({required this.hsv, required this.onChanged});

  final HSVColor hsv;
  final ValueChanged<HSVColor> onChanged;

  static const double _height = 14;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final width = box.maxWidth;
      void pick(Offset p) =>
          onChanged(hsv.withHue((p.dx / width).clamp(0.0, 1.0) * 359.9));
      return GestureDetector(
        onPanDown: (d) => pick(d.localPosition),
        onPanUpdate: (d) => pick(d.localPosition),
        child: SizedBox(
          height: 22,
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: _height,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(_height),
                  gradient: LinearGradient(colors: [
                    for (var h = 0; h <= 360; h += 60)
                      HSVColor.fromAHSV(1, h % 360 * 1.0, 1, 1).toColor(),
                  ]),
                ),
              ),
              Positioned(
                left: hsv.hue / 360 * width - 11,
                child: _Thumb(HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
          boxShadow: const [
            BoxShadow(
                color: Color(0x44000000), blurRadius: 4, offset: Offset(0, 1))
          ],
        ),
      );
}

/// Old colour on the left, new on the right, like Word's preview.
class _Compare extends StatelessWidget {
  const _Compare({required this.before, required this.after});

  final Color before;
  final Color after;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 56,
          height: 40,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: ColoredBox(color: before)),
              Expanded(child: ColoredBox(color: after)),
            ],
          ),
        ),
      );
}

String _hexOf(Color c) => _hex(c).toUpperCase();

String _hex(Color c) {
  String channel(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '${channel(c.r)}${channel(c.g)}${channel(c.b)}';
}
