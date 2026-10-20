import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'geometry.dart';
import 'signature_data.dart';
import 'signature_style.dart';
import 'smart_enhancer.dart';
import 'stroke_renderer.dart';

/// How the eraser works.
enum EraserMode {
  /// Rubs out only the ink under the eraser, splitting lines where needed.
  partial,

  /// Removes every stroke the eraser touches, whole.
  stroke,
}

/// Holds the strokes of a [SignaturePad], with undo/redo, enhancement and
/// export.
///
/// Listeners are notified when strokes are added or removed and when a
/// setting changes, not for every point while drawing.
class SignatureController extends ChangeNotifier {
  SignatureController({
    SignatureStyle style = const SignatureStyle(),
    SignatureEnhancer enhancer = const SmartEnhancer(),
    bool enhance = true,
    SignatureData? initial,
  })  : _style = style,
        _enhancer = enhancer,
        _enhance = enhance {
    if (initial != null) _history[0] = initial.strokes;
  }

  static const int _maxHistory = 100;
  static const double _eraserRadius = 10;
  // closer than this to the previous point adds nothing but noise
  static const double _minPointDistance = 0.5;

  final List<List<SignatureStroke>> _history = [const []];
  var _index = 0;
  List<SignatureStroke>? _display;

  SignatureStyle _style;
  SignatureStyle get style => _style;
  set style(SignatureStyle value) {
    if (value == _style) return;
    _style = value;
    notifyListeners();
  }

  SignatureEnhancer _enhancer;
  SignatureEnhancer get enhancer => _enhancer;
  set enhancer(SignatureEnhancer value) {
    _enhancer = value;
    _display = null;
    notifyListeners();
  }

  bool _enhance;

  /// Show and export the enhanced signature. When off you get exactly what
  /// was drawn, handy as a before/after toggle.
  bool get enhance => _enhance;
  set enhance(bool value) {
    if (value == _enhance) return;
    _enhance = value;
    _display = null;
    notifyListeners();
  }

  /// The strokes as drawn.
  List<SignatureStroke> get strokes => _erasePreview ?? _history[_index];

  /// What the pad shows: enhanced strokes, or the raw ones with [enhance] off.
  List<SignatureStroke> get displayStrokes => _display ??=
      _enhance ? _enhancer.enhance(SignatureData(strokes)).strokes : strokes;

  bool get isEmpty => strokes.isEmpty;
  bool get isNotEmpty => strokes.isNotEmpty;
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _history.length - 1;

  void undo() {
    if (!canUndo) return;
    _index--;
    _changed();
  }

  void redo() {
    if (!canRedo) return;
    _index++;
    _changed();
  }

  /// Removes every stroke. Undoable.
  void clear() {
    if (isNotEmpty) _commit(const []);
  }

  /// Replaces the signature, e.g. with one saved earlier via [toData].
  void load(SignatureData data) => _commit(data.strokes);

  /// The raw strokes, ready for [SignatureData.toJson].
  SignatureData toData() => SignatureData(strokes);

  /// The signature as it will be exported: enhanced and straightened when
  /// [enhance] is on, otherwise the raw strokes.
  SignatureData export() => _enhance
      ? _enhancer.finalize(SignatureData(strokes))
      : SignatureData(strokes);

  // ---- drawing, driven by SignaturePad ----

  final _active = _ActiveStroke();

  /// The stroke being drawn right now. Fires on every point.
  Listenable get activeStroke => _active;
  List<SignaturePoint>? get activePoints => _active.points;

  void beginStroke(SignaturePoint point) {
    _active.points = [point];
    _active.ping();
  }

  void addPoint(SignaturePoint point) {
    final points = _active.points;
    if (points == null) return;
    final gap = (points.last.offset - point.offset).distance;
    if (gap < _minPointDistance) return;
    points.add(point);
    _active.ping();
  }

  void endStroke() {
    final points = _active.points;
    if (points == null) return;
    _active.points = null;
    _commit([...strokes, SignatureStroke(points)]);
    _active.ping();
  }

  void cancelStroke() {
    if (_active.points == null) return;
    _active.points = null;
    _active.ping();
  }

  bool _erasing = false;

  /// When on, the pad erases instead of drawing.
  bool get erasing => _erasing;
  set erasing(bool value) {
    if (value == _erasing) return;
    _erasing = value;
    notifyListeners();
  }

  EraserMode _eraserMode = EraserMode.partial;

  /// Whether the eraser rubs out just what it touches or whole strokes.
  EraserMode get eraserMode => _eraserMode;
  set eraserMode(EraserMode value) {
    if (value == _eraserMode) return;
    _eraserMode = value;
    notifyListeners();
  }

  // strokes while an erase drag is in progress, committed as one undo step
  List<SignatureStroke>? _erasePreview;

  /// Where the eraser is during a drag, for drawing its outline.
  Offset? get eraserPosition => _active.eraser;

  /// Eraser radius in logical pixels, a comfortable fingertip by default.
  double get eraserRadius => math.max(_style.width * 2.5, _eraserRadius);

  /// Starts an erase gesture at [point]. Changes show right away but only
  /// become one undo step on [endErase].
  void beginErase(Offset point) {
    _erasePreview = _history[_index];
    eraseAt(point);
  }

  /// Erases around [point] using [eraserMode]. Outside a gesture this is a
  /// single undoable erase. Returns whether anything was removed.
  bool eraseAt(Offset point, {double? radius}) {
    final reach = radius ?? eraserRadius;
    final standalone = _erasePreview == null;
    final current = strokes;
    final next = <SignatureStroke>[];
    var changed = false;
    if (_eraserMode == EraserMode.stroke) {
      next.addAll(current.where((s) => !_touches(s, point, reach)));
      changed = next.length != current.length;
    } else {
      for (final stroke in current) {
        final pieces = _rubOut(stroke, point, reach);
        if (pieces.length != 1 || !identical(pieces.first, stroke)) {
          changed = true;
        }
        next.addAll(pieces);
      }
    }
    if (standalone) {
      if (changed) _commit(next);
      return changed;
    }
    _active
      ..eraser = point
      ..ping();
    if (changed) {
      _erasePreview = next;
      _changed();
    }
    return changed;
  }

  /// Finishes an erase gesture as one undo step.
  void endErase() {
    final next = _erasePreview;
    if (next == null) return;
    _erasePreview = null;
    _active
      ..eraser = null
      ..ping();
    if (identical(next, _history[_index])) return;
    _commit(next);
  }

  /// Abandons an erase gesture, putting everything back.
  void cancelErase() {
    if (_erasePreview == null) return;
    _erasePreview = null;
    _active
      ..eraser = null
      ..ping();
    _changed();
  }

  // leftovers shorter than this are crumbs, not ink worth keeping
  static const double _minPiece = 3;
  // fine enough that the eraser can't skip between sparse raw points
  static const double _eraseSpacing = 1.5;

  /// [stroke] with the part within [reach] of [point] removed. Returns the
  /// same instance when untouched, so unchanged strokes keep their identity.
  static List<SignatureStroke> _rubOut(
      SignatureStroke stroke, Offset point, double reach) {
    if (!_touches(stroke, point, reach)) return [stroke];
    if (stroke.points.length == 1) return const [];
    final pieces = <SignatureStroke>[];
    var run = <SignaturePoint>[];
    void flush() {
      if (run.length >= 2) {
        final piece = SignatureStroke(run);
        if (piece.length >= _minPiece) pieces.add(piece);
      }
      run = [];
    }

    for (final p in resample(stroke.points, _eraseSpacing)) {
      if ((p.offset - point).distance <= reach) {
        flush();
      } else {
        run.add(p);
      }
    }
    flush();
    return pieces;
  }

  static bool _touches(SignatureStroke stroke, Offset point, double reach) {
    final points = stroke.points;
    if (!stroke.bounds.inflate(reach).contains(point)) return false;
    if (points.length == 1) {
      return (points.first.offset - point).distance <= reach;
    }
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1].offset, b = points[i].offset;
      final ab = b - a;
      final lengthSquared = ab.distanceSquared;
      final t = lengthSquared == 0
          ? 0.0
          : (((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) /
                  lengthSquared)
              .clamp(0.0, 1.0);
      if ((point - (a + ab * t)).distance <= reach) return true;
    }
    return false;
  }

  void _commit(List<SignatureStroke> next) {
    _history
      ..removeRange(_index + 1, _history.length)
      ..add(List.unmodifiable(next));
    if (_history.length > _maxHistory) _history.removeAt(0);
    _index = _history.length - 1;
    _changed();
  }

  void _changed() {
    _display = null;
    notifyListeners();
  }

  // ---- export ----

  /// Renders [export] cropped to the ink, [padding] logical pixels around it.
  /// Returns null when the pad is empty.
  ///
  /// [inkColor] overrides the ink, e.g. dark ink for a document when the
  /// user signed in dark mode.
  Future<ui.Image?> toImage({
    double pixelRatio = 3,
    double padding = 12,
    Color? background,
    Color? inkColor,
  }) async {
    final data = export();
    if (data.isEmpty) return null;
    final area = _exportArea(data, padding);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(pixelRatio)
      ..translate(-area.left, -area.top);
    if (background != null) canvas.drawRect(area, Paint()..color = background);
    final style = inkColor == null ? _style : _style.copyWith(color: inkColor);
    paintStrokes(canvas, data.strokes, style, ink: _enhance);
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(
        math.max(1, (area.width * pixelRatio).ceil()),
        math.max(1, (area.height * pixelRatio).ceil()),
      );
    } finally {
      picture.dispose();
    }
  }

  /// [toImage] encoded as PNG. Transparent unless you pass a [background].
  Future<Uint8List?> toPngBytes({
    double pixelRatio = 3,
    double padding = 12,
    Color? background,
    Color? inkColor,
  }) async {
    final image = await toImage(
      pixelRatio: pixelRatio,
      padding: padding,
      background: background,
      inkColor: inkColor,
    );
    if (image == null) return null;
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      return bytes?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// [export] as a standalone SVG document, or null when empty. [inkColor]
  /// works as in [toImage].
  String? toSvg({double padding = 12, Color? background, Color? inkColor}) {
    final data = export();
    if (data.isEmpty) return null;
    final area = _exportArea(data, padding);
    final ink = inkColor ?? _style.color;
    final fill = _hex(ink);
    final opacity =
        ink.a < 1 ? ' fill-opacity="${ink.a.toStringAsFixed(3)}"' : '';
    final b = StringBuffer()
      ..write('<svg xmlns="http://www.w3.org/2000/svg" ')
      ..write('width="${_d(area.width)}" height="${_d(area.height)}" ')
      ..write(
          'viewBox="${_d(area.left)} ${_d(area.top)} ${_d(area.width)} ${_d(area.height)}">');
    if (background != null) {
      b.write(
          '<rect x="${_d(area.left)}" y="${_d(area.top)}" width="${_d(area.width)}" '
          'height="${_d(area.height)}" fill="${_hex(background)}"/>');
    }
    b.write('<g fill="$fill"$opacity>');
    for (final stroke in data.strokes) {
      for (final shape in inkShapes(stroke, _style, ink: _enhance)) {
        switch (shape) {
          case InkDot(:final center, :final radius):
            b.write(
                '<circle cx="${_d(center.dx)}" cy="${_d(center.dy)}" r="${_d(radius)}"/>');
          case InkRibbon():
            b.write('<path d="${ribbonSvg(shape)}"/>');
        }
      }
    }
    return (b..write('</g></svg>')).toString();
  }

  Rect _exportArea(SignatureData data, double padding) =>
      data.bounds.inflate(maxInkWidth(_style) / 2 + padding);

  @override
  void dispose() {
    _active.dispose();
    super.dispose();
  }
}

class _ActiveStroke extends ChangeNotifier {
  List<SignaturePoint>? points;
  Offset? eraser;

  void ping() => notifyListeners();
}

String _hex(Color c) {
  String channel(double v) =>
      (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${channel(c.r)}${channel(c.g)}${channel(c.b)}';
}

String _d(double v) => v.toStringAsFixed(2);
