import 'package:flutter/material.dart';

import 'color_panel.dart';
import 'field_panels.dart';
import 'signature_controller.dart';
import 'signature_pad.dart';
import 'signature_style.dart';
import 'smart_enhancer.dart';

/// Buttons that can appear in the [SignatureField] toolbar.
enum SignatureTool { enhance, ink, color, width, eraser, undo, redo, clear }

/// A named stroke width for the width panel.
@immutable
class SignatureWidth {
  const SignatureWidth(this.label, this.width);

  final String label;
  final double width;
}

/// Every piece of text in the field. Override to localise.
@immutable
class SignatureFieldLabels {
  const SignatureFieldLabels({
    this.hint = 'Sign here',
    this.enhance = 'Enhance',
    this.enhanceSettings = 'Enhance settings',
    this.ink = 'Ink',
    this.color = 'Colour',
    this.width = 'Width',
    this.eraser = 'Eraser',
    this.eraserSettings = 'Eraser settings',
    this.eraserPartial = 'Partial',
    this.eraserPartialDescription = 'Rubs out only what you touch',
    this.eraserStroke = 'Whole stroke',
    this.eraserStrokeDescription = 'Removes the full line in one go',
    this.undo = 'Undo',
    this.redo = 'Redo',
    this.clear = 'Clear',
    this.ballpoint = 'Ballpoint',
    this.fountain = 'Fountain',
    this.marker = 'Marker',
    this.ballpointDescription = 'Responds to speed, tapered ends',
    this.fountainDescription = 'Calligraphy nib, thick and thin',
    this.markerDescription = 'Even line everywhere',
    this.inkColors = 'Ink colours',
    this.themeColors = 'Theme colours',
    this.standardColors = 'Standard colours',
    this.recentColors = 'Recent colours',
    this.moreColors = 'More colours…',
    this.customColor = 'Custom colour',
    this.custom = 'Custom',
    this.enhanceTitle = 'Smart enhance',
    this.enhanceSubtitle = 'Cleans up every stroke',
    this.smoothing = 'Smoothing',
    this.natural = 'Natural',
    this.smooth = 'Smooth',
    this.removeHooks = 'Remove pen hooks',
    this.removeStrayMarks = 'Remove stray marks',
    this.straighten = 'Straighten on export',
    this.cancel = 'Cancel',
    this.select = 'Select',
  });

  /// Shown on the empty pad. An empty string hides it.
  final String hint;
  final String enhance;
  final String enhanceSettings;
  final String ink;
  final String color;
  final String width;
  final String eraser;
  final String eraserSettings;
  final String eraserPartial;
  final String eraserPartialDescription;
  final String eraserStroke;
  final String eraserStrokeDescription;
  final String undo;
  final String redo;
  final String clear;
  final String ballpoint;
  final String fountain;
  final String marker;
  final String ballpointDescription;
  final String fountainDescription;
  final String markerDescription;
  final String inkColors;
  final String themeColors;
  final String standardColors;
  final String recentColors;
  final String moreColors;
  final String customColor;
  final String custom;
  final String enhanceTitle;
  final String enhanceSubtitle;
  final String smoothing;
  final String natural;
  final String smooth;
  final String removeHooks;
  final String removeStrayMarks;
  final String straighten;
  final String cancel;
  final String select;

  String inkName(InkStyle ink) => switch (ink) {
        InkStyle.ballpoint => ballpoint,
        InkStyle.fountain => fountain,
        InkStyle.marker => marker,
      };

  String inkDescription(InkStyle ink) => switch (ink) {
        InkStyle.ballpoint => ballpointDescription,
        InkStyle.fountain => fountainDescription,
        InkStyle.marker => markerDescription,
      };
}

/// A ready to use signature input: a formatting toolbar on top of a
/// [SignaturePad], in one bordered box like a text field. Follows the app's
/// light or dark theme.
///
/// Read the result from the [controller], e.g. `controller.toPngBytes()`.
class SignatureField extends StatefulWidget {
  const SignatureField({
    super.key,
    this.controller,
    this.height = 200,
    this.tools = const {...SignatureTool.values},
    this.colors,
    this.widths = defaultWidths,
    this.labels = const SignatureFieldLabels(),
    this.padColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
    this.enabled = true,
    this.onChanged,
  });

  /// Created and disposed by the field when null.
  final SignatureController? controller;

  /// Height of the signing area, the toolbar comes on top of it.
  final double height;

  /// Which toolbar buttons to show, in their fixed order. An empty set hides
  /// the toolbar.
  final Set<SignatureTool> tools;

  /// Ink colours offered first in the colour panel. Defaults to
  /// [lightInks] or [darkInks] depending on the theme.
  final List<Color>? colors;

  /// Presets in the width panel.
  final List<SignatureWidth> widths;

  final SignatureFieldLabels labels;

  /// Background of the signing area. Defaults to white paper in light mode
  /// and a dark surface in dark mode.
  final Color? padColor;

  final BorderRadius borderRadius;

  /// When false the toolbar and pad ignore input.
  final bool enabled;

  /// Called when strokes are added or removed, or a setting changes.
  final ValueChanged<SignatureController>? onChanged;

  /// Pen inks that read well on white.
  static const lightInks = [
    Color(0xFF1C2A5A), // blue-black
    Color(0xFF111111), // black
    Color(0xFF1E4FD8), // royal blue
    Color(0xFF7A1F2B), // burgundy
  ];

  /// The same pens, lightened to read on a dark pad.
  static const darkInks = [
    Color(0xFFE6EAF5),
    Color(0xFFFFFFFF),
    Color(0xFF8AB4F8),
    Color(0xFFF2A7B0),
  ];

  static const defaultWidths = [
    SignatureWidth('Fine', 1.8),
    SignatureWidth('Medium', 2.6),
    SignatureWidth('Bold', 4),
  ];

  @override
  State<SignatureField> createState() => _SignatureFieldState();
}

class _SignatureFieldState extends State<SignatureField> {
  SignatureController? _own;
  SignatureController get _controller => widget.controller ?? _own!;
  final _recent = <Color>[];
  Brightness? _brightness;

  static const int _maxRecent = 10;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _own = SignatureController();
    _controller.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    if (brightness == _brightness) return;
    _brightness = brightness;
    // after the frame, the controller may have listeners up the tree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _adaptInk(brightness);
    });
  }

  /// Swaps a default ink for its light or dark counterpart, so a signature
  /// started in one theme stays visible in the other.
  void _adaptInk(Brightness brightness) {
    if (widget.colors != null) return;
    final from = brightness == Brightness.dark
        ? SignatureField.lightInks
        : SignatureField.darkInks;
    final to = brightness == Brightness.dark
        ? SignatureField.darkInks
        : SignatureField.lightInks;
    final i = from.indexOf(_controller.style.color);
    if (i != -1) _controller.style = _controller.style.copyWith(color: to[i]);
  }

  @override
  void didUpdateWidget(SignatureField old) {
    super.didUpdateWidget(old);
    if (old.controller == widget.controller) return;
    (old.controller ?? _own)?.removeListener(_changed);
    if (widget.controller != null) {
      _own?.dispose();
      _own = null;
    } else {
      _own ??= SignatureController();
    }
    _controller.addListener(_changed);
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _own?.dispose();
    super.dispose();
  }

  void _changed() {
    setState(() {});
    widget.onChanged?.call(_controller);
  }

  void _remember(Color color) {
    _recent
      ..remove(color)
      ..insert(0, color);
    if (_recent.length > _maxRecent) _recent.removeLast();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final border = scheme.outlineVariant;
    final inks = widget.colors ??
        (dark ? SignatureField.darkInks : SignatureField.lightInks);
    // the border goes on top, otherwise the pad would paint over it
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: widget.borderRadius,
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.tools.isNotEmpty) ...[
              ColoredBox(
                color:
                    dark ? scheme.surfaceContainer : scheme.surfaceContainerLow,
                child: _Toolbar(
                  controller: _controller,
                  tools: widget.tools,
                  inks: inks,
                  recent: _recent,
                  widths: widget.widths,
                  labels: widget.labels,
                  enabled: widget.enabled,
                  onCustomColor: _remember,
                ),
              ),
              Divider(height: 1, thickness: 1, color: border),
            ],
            SizedBox(
              height: widget.height,
              child: SignaturePad(
                controller: _controller,
                backgroundColor: widget.padColor,
                borderRadius: BorderRadius.zero,
                hint: widget.labels.hint.isEmpty ? null : widget.labels.hint,
                enabled: widget.enabled,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.tools,
    required this.inks,
    required this.recent,
    required this.widths,
    required this.labels,
    required this.enabled,
    required this.onCustomColor,
  });

  final SignatureController controller;
  final Set<SignatureTool> tools;
  final List<Color> inks;
  final List<Color> recent;
  final List<SignatureWidth> widths;
  final SignatureFieldLabels labels;
  final bool enabled;
  final ValueChanged<Color> onCustomColor;

  static const double _height = 48;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final style = c.style;
    bool has(SignatureTool t) => tools.contains(t);
    // picking pen settings means you want to draw again
    void setStyle(SignatureStyle s) {
      c
        ..erasing = false
        ..style = s;
    }

    final enhancer = c.enhancer;
    final pen = [
      if (has(SignatureTool.ink))
        _Popover(
          key: const ValueKey(SignatureTool.ink),
          tooltip: labels.ink,
          enabled: enabled,
          trigger: Icon(_inkIcon(style.ink), size: 20),
          panel: (close) => InkPanel(
            style: style,
            labels: labels,
            onSelected: (ink) {
              setStyle(style.copyWith(ink: ink));
              close();
            },
          ),
        ),
      if (has(SignatureTool.color))
        _Popover(
          key: const ValueKey(SignatureTool.color),
          tooltip: labels.color,
          enabled: enabled,
          trigger: _ColorDot(style.color),
          panel: (close) => ColorPanel(
            inks: inks,
            recent: recent,
            selected: style.color,
            labels: labels,
            onSelected: (color) {
              setStyle(style.copyWith(color: color));
              close();
            },
            onMore: () async {
              close();
              final color =
                  await showCustomColorDialog(context, style.color, labels);
              if (color == null) return;
              onCustomColor(color);
              setStyle(c.style.copyWith(color: color));
            },
          ),
        ),
      if (has(SignatureTool.width))
        _Popover(
          key: const ValueKey(SignatureTool.width),
          tooltip: labels.width,
          enabled: enabled,
          trigger: const Icon(Icons.line_weight, size: 20),
          panel: (close) => WidthPanel(
            style: style,
            widths: widths,
            labels: labels,
            onChanged: (w) => setStyle(c.style.copyWith(width: w)),
          ),
        ),
      if (has(SignatureTool.eraser)) ...[
        _ToolButton(
          key: const ValueKey(SignatureTool.eraser),
          tooltip: labels.eraser,
          icon: const _EraserIcon(),
          selected: c.erasing,
          onPressed: enabled ? () => c.erasing = !c.erasing : null,
        ),
        _Popover(
          tooltip: labels.eraserSettings,
          enabled: enabled,
          compact: true,
          trigger: const SizedBox.shrink(),
          panel: (close) => EraserPanel(
            mode: c.eraserMode,
            labels: labels,
            onSelected: (mode) {
              c
                ..eraserMode = mode
                ..erasing = true;
              close();
            },
          ),
        ),
      ],
    ];
    final format = <Widget>[
      if (has(SignatureTool.enhance)) ...[
        _ToolButton(
          key: const ValueKey(SignatureTool.enhance),
          tooltip: labels.enhance,
          icon: const Icon(Icons.auto_fix_high),
          selected: c.enhance,
          onPressed: enabled ? () => c.enhance = !c.enhance : null,
        ),
        _Popover(
          tooltip: labels.enhanceSettings,
          enabled: enabled,
          compact: true,
          trigger: const SizedBox.shrink(),
          panel: (close) => EnhancePanel(
            enabled: c.enhance,
            options: enhancer is SmartEnhancer ? enhancer.options : null,
            labels: labels,
            onEnabled: (v) => c.enhance = v,
            onOptions: (o) => c.enhancer = SmartEnhancer(options: o),
          ),
        ),
        if (pen.isNotEmpty) const _Separator(),
      ],
      ...pen,
    ];
    final history = <Widget>[
      if (has(SignatureTool.undo))
        _ToolButton(
          key: const ValueKey(SignatureTool.undo),
          tooltip: labels.undo,
          icon: const Icon(Icons.undo_rounded),
          onPressed: enabled && c.canUndo ? c.undo : null,
        ),
      if (has(SignatureTool.redo))
        _ToolButton(
          key: const ValueKey(SignatureTool.redo),
          tooltip: labels.redo,
          icon: const Icon(Icons.redo_rounded),
          onPressed: enabled && c.canRedo ? c.redo : null,
        ),
      if (has(SignatureTool.clear))
        _ToolButton(
          key: const ValueKey(SignatureTool.clear),
          tooltip: labels.clear,
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: enabled && c.isNotEmpty ? c.clear : null,
        ),
    ];
    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            // scrolls rather than overflows on very narrow layouts
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: format),
              ),
            ),
            ...history,
          ],
        ),
      ),
    );
  }

  static IconData _inkIcon(InkStyle ink) => switch (ink) {
        InkStyle.ballpoint => Icons.edit_outlined,
        InkStyle.fountain => Icons.draw_outlined,
        InkStyle.marker => Icons.brush_outlined,
      };
}

/// Rounded square button with a tonal fill when [selected].
class _ToolButton extends StatelessWidget {
  const _ToolButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final Widget icon;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = onPressed == null
        ? scheme.onSurface.withValues(alpha: 0.3)
        : selected
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: selected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onPressed,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? scheme.secondaryContainer : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(size: 20, color: color),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A toolbar button that opens a floating panel.
class _Popover extends StatefulWidget {
  const _Popover({
    super.key,
    required this.tooltip,
    required this.enabled,
    required this.trigger,
    required this.panel,
    this.compact = false,
  });

  final String tooltip;
  final bool enabled;
  final Widget trigger;
  final Widget Function(VoidCallback close) panel;

  /// Just a chevron, attached to the button before it.
  final bool compact;

  @override
  State<_Popover> createState() => _PopoverState();
}

class _PopoverState extends State<_Popover> {
  final _menu = MenuController();
  var _open = false;

  void _setOpen(bool open) {
    if (mounted) setState(() => _open = open);
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final enabled = widget.enabled;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // system back closes the panel instead of leaving the screen
    return PopScope(
      canPop: !_open,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _menu.close();
      },
      child: MenuAnchor(
        controller: _menu,
        onOpen: () => _setOpen(true),
        onClose: () => _setOpen(false),
        alignmentOffset: const Offset(0, 6),
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(dark
              ? scheme.surfaceContainerHigh
              : scheme.surfaceContainerLowest),
          elevation: const WidgetStatePropertyAll(8),
          shadowColor:
              WidgetStatePropertyAll(scheme.shadow.withValues(alpha: 0.5)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6)),
            ),
          ),
        ),
        menuChildren: [widget.panel(_menu.close)],
        builder: (context, menu, _) {
          final open = menu.isOpen;
          final color = enabled
              ? scheme.onSurfaceVariant
              : scheme.onSurface.withValues(alpha: 0.3);
          return Tooltip(
            message: widget.tooltip,
            child: Semantics(
              button: true,
              expanded: open,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: enabled
                        ? () => open ? menu.close() : menu.open()
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      height: 36,
                      padding: EdgeInsets.only(
                          left: compact ? 0 : 8, right: compact ? 0 : 2),
                      decoration: BoxDecoration(
                        color: open ? scheme.surfaceContainerHighest : null,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconTheme.merge(
                              data: IconThemeData(color: color),
                              child: widget.trigger),
                          AnimatedRotation(
                            turns: open ? 0.5 : 0,
                            duration: const Duration(milliseconds: 160),
                            child: Icon(Icons.expand_more_rounded,
                                size: 18, color: color),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Separator extends StatelessWidget {
  const _Separator();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: Theme.of(context).colorScheme.outlineVariant,
      );
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 20,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: Theme.of(context).colorScheme.outline, width: 1.2),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      );
}

/// Material Icons has no eraser, so draw one: a tilted block with a band.
class _EraserIcon extends StatelessWidget {
  const _EraserIcon();

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final size = icon.size ?? 20;
    return CustomPaint(
      size: Size.square(size),
      painter: _EraserPainter(icon.color ?? const Color(0xFF000000)),
    );
  }
}

class _EraserPainter extends CustomPainter {
  const _EraserPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8 * u
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..save()
      ..translate(12 * u, 11 * u)
      ..rotate(-0.785);
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 17 * u, height: 9 * u),
      Radius.circular(2 * u),
    );
    canvas
      ..drawRRect(body, line)
      // the rubber tip, filled
      ..drawRRect(
        RRect.fromLTRBAndCorners(
          -8.5 * u,
          -4.5 * u,
          -2.5 * u,
          4.5 * u,
          topLeft: Radius.circular(2 * u),
          bottomLeft: Radius.circular(2 * u),
        ),
        Paint()..color = color,
      )
      ..restore()
      ..drawLine(Offset(4 * u, 21 * u), Offset(20 * u, 21 * u), line);
  }

  @override
  bool shouldRepaint(_EraserPainter old) => old.color != color;
}
