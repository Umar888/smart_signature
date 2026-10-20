import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// How the ink responds to the pen.
enum InkStyle {
  /// Thinner when you move fast, thicker when slow, tapered ends.
  ballpoint,

  /// Calligraphy nib: thick or thin depending on the stroke direction.
  fountain,

  /// Even width everywhere.
  marker,
}

/// Look of the signature ink.
@immutable
class SignatureStyle {
  const SignatureStyle({
    this.color = const Color(0xFF1C2A5A),
    this.width = 2.6,
    this.ink = InkStyle.ballpoint,
    this.nibAngle = -math.pi / 4,
  }) : assert(width > 0);

  /// Ink colour. The default is a blue-black pen.
  final Color color;

  /// Base stroke width in logical pixels.
  final double width;

  final InkStyle ink;

  /// Angle of the [InkStyle.fountain] nib in radians. Strokes across the nib
  /// are thick, strokes along it are hairlines.
  final double nibAngle;

  SignatureStyle copyWith(
          {Color? color, double? width, InkStyle? ink, double? nibAngle}) =>
      SignatureStyle(
        color: color ?? this.color,
        width: width ?? this.width,
        ink: ink ?? this.ink,
        nibAngle: nibAngle ?? this.nibAngle,
      );

  @override
  bool operator ==(Object other) =>
      other is SignatureStyle &&
      other.color == color &&
      other.width == width &&
      other.ink == ink &&
      other.nibAngle == nibAngle;

  @override
  int get hashCode => Object.hash(color, width, ink, nibAngle);
}
