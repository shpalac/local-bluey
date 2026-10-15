import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../link/models.dart';

/// Platform-independent artwork. All motion comes from the host's finite
/// animation phase, so screenshots and reduce-motion renders are deterministic.
class JoyfulBlueyPainter extends CustomPainter {
  const JoyfulBlueyPainter({
    required this.gazeX,
    required this.gazeY,
    required this.talk,
    required this.mood,
    required this.awake,
    required this.tint,
    required this.phase,
  });

  final double gazeX;
  final double gazeY;
  final double talk;
  final Mood mood;
  final bool awake;
  final Color tint;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final side = math.min(size.width, size.height);
    canvas.save();
    canvas.translate((size.width - side) / 2, (size.height - side) / 2);
    canvas.scale(side / 320, side / 320);

    final sleepy = !awake || mood == Mood.sleepy || mood == Mood.resting;
    final joyful = mood == Mood.happy || mood == Mood.pointing;
    final wave = awake ? math.sin(phase * math.pi * 2) : 0.0;
    canvas.translate(0, awake ? -3 * wave.abs() : 3);
    canvas.rotate(awake ? wave * 0.018 : -0.025);

    // Tail and orange toes sit behind the fluffy body.
    _shape(
      canvas,
      Path()
        ..moveTo(207, 222)
        ..quadraticBezierTo(255, 226, 273, 270)
        ..quadraticBezierTo(273, 241, 254, 218)
        ..quadraticBezierTo(282, 242, 292, 226)
        ..quadraticBezierTo(258, 188, 223, 200)
        ..close(),
      const Color(0xFF236DC5),
    );
    for (final x in <double>[123, 196]) {
      _shape(
        canvas,
        Path()
          ..moveTo(x - 5, 252)
          ..lineTo(x - 7, 266)
          ..quadraticBezierTo(x - 30, 262, x - 29, 282)
          ..quadraticBezierTo(x - 24, 293, x - 7, 285)
          ..quadraticBezierTo(x + 11, 296, x + 21, 284)
          ..quadraticBezierTo(x + 32, 270, x + 7, 265)
          ..lineTo(x + 5, 251)
          ..close(),
        const Color(0xFFFFA82C),
        stroke: const Color(0xFFD76B15),
        width: 3,
      );
    }

    _oval(
      canvas,
      const Rect.fromLTWH(85, 123, 150, 164),
      const Color(0xFF2055AA),
    );
    _ovalGradient(canvas, const Rect.fromLTWH(89, 124, 142, 157), [
      Color.lerp(const Color(0xFF7DE9FF), tint, 0.10)!,
      const Color(0xFF348DE7),
      const Color(0xFF184696),
    ]);

    _wing(canvas, left: true, wave: wave, joyful: joyful);
    _wing(canvas, left: false, wave: wave, joyful: joyful);

    _ovalGradient(canvas, const Rect.fromLTWH(112, 177, 96, 101), [
      const Color(0xFFFFFFFF),
      const Color(0xFFD7F7FF),
      const Color(0xFF75C8F5),
    ]);

    // Three distinct, windswept crest feathers.
    _shape(
      canvas,
      Path()
        ..moveTo(145, 58)
        ..quadraticBezierTo(127, 31, 135, 13)
        ..quadraticBezierTo(156, 24, 160, 48)
        ..quadraticBezierTo(169, 10, 191, 12)
        ..quadraticBezierTo(191, 34, 174, 52)
        ..quadraticBezierTo(199, 36, 209, 44)
        ..quadraticBezierTo(201, 59, 176, 67)
        ..close(),
      const Color(0xFF197DDE),
      stroke: const Color(0xFF1353A4),
      width: 3,
    );

    _oval(
      canvas,
      const Rect.fromLTWH(66, 34, 188, 186),
      const Color(0xFF174285),
    );
    _ovalGradient(canvas, const Rect.fromLTWH(70, 37, 180, 178), [
      Color.lerp(const Color(0xFF93EEFF), tint, 0.12)!,
      Color.lerp(const Color(0xFF449BEE), tint, 0.08)!,
      const Color(0xFF1A4E9C),
    ]);

    for (final x in <double>[106, 215]) {
      _oval(
        canvas,
        Rect.fromCenter(center: Offset(x, 176), width: 36, height: 21),
        const Color(0xFFFFB4CA).withValues(alpha: sleepy ? 0.18 : 0.48),
      );
    }

    _line(
      canvas,
      Path()
        ..moveTo(89, 104)
        ..quadraticBezierTo(108, mood == Mood.thinking ? 102 : 87, 131, 104),
      const Color(0xFF173A7C),
      6,
    );
    _line(
      canvas,
      Path()
        ..moveTo(187, 104)
        ..quadraticBezierTo(211, joyful ? 80 : 87, 231, 104),
      const Color(0xFF173A7C),
      6,
    );

    _eye(canvas, 119, 138, sleepy: sleepy);
    _eye(canvas, 205, 138, sleepy: sleepy);

    final opening = mood == Mood.talking && awake
        ? 12 + 30 * talk
        : joyful
        ? 39.0
        : 23.0;
    // Draw the smiling mouth first so the beak sits naturally over it.
    _oval(
      canvas,
      Rect.fromCenter(
        center: const Offset(160, 190),
        width: 52,
        height: opening,
      ),
      const Color(0xFF65203B),
    );
    if (!sleepy && opening > 25) {
      _oval(
        canvas,
        const Rect.fromLTWH(147, 200, 26, 9),
        const Color(0xFFFF829C),
      );
    }
    _shape(
      canvas,
      Path()
        ..moveTo(117, 177)
        ..quadraticBezierTo(136, 151, 160, 155)
        ..quadraticBezierTo(184, 151, 204, 177)
        ..quadraticBezierTo(179, 188, 160, 185)
        ..quadraticBezierTo(140, 189, 117, 177)
        ..close(),
      const Color(0xFFFFB638),
      stroke: const Color(0xFFE77A16),
      width: 3,
    );
    _line(
      canvas,
      Path()
        ..moveTo(160, 166)
        ..lineTo(160, 184),
      const Color(0xFFF58C1C),
      2,
    );
    _shape(
      canvas,
      Path()
        ..moveTo(160, 235)
        ..lineTo(165, 244)
        ..lineTo(175, 246)
        ..lineTo(168, 254)
        ..lineTo(170, 263)
        ..lineTo(160, 258)
        ..lineTo(150, 263)
        ..lineTo(152, 254)
        ..lineTo(145, 246)
        ..lineTo(155, 244)
        ..close(),
      const Color(0xFFE3FAFF),
    );
    if (sleepy) {
      _oval(
        canvas,
        const Rect.fromLTWH(69, 37, 182, 181),
        const Color(0xFF122A68).withValues(alpha: 0.20),
      );
    }
    canvas.restore();
  }

  void _wing(
    Canvas canvas, {
    required bool left,
    required double wave,
    required bool joyful,
  }) {
    canvas.save();
    final anchor = left ? const Offset(104, 183) : const Offset(216, 183);
    canvas.translate(anchor.dx, anchor.dy);
    canvas.rotate((left ? -1 : 1) * (joyful ? 0.13 : 0.02 + wave * 0.12));
    if (!left) canvas.scale(-1, 1);
    _shape(
      canvas,
      Path()
        ..moveTo(5, -12)
        ..quadraticBezierTo(-24, -18, -55, -57)
        ..quadraticBezierTo(-66, -63, -61, -30)
        ..quadraticBezierTo(-84, -45, -95, -59)
        ..quadraticBezierTo(-102, -30, -76, -13)
        ..quadraticBezierTo(-98, -16, -110, -8)
        ..quadraticBezierTo(-89, 19, -58, 18)
        ..quadraticBezierTo(-25, 44, 12, 24)
        ..close(),
      const Color(0xFF348FEB),
      stroke: const Color(0xFF174A9B),
      width: 3,
    );
    _line(
      canvas,
      Path()
        ..moveTo(-72, 0)
        ..quadraticBezierTo(-38, 28, 0, 10),
      const Color(0xFF7DDDFB),
      6,
    );
    canvas.restore();
  }

  void _eye(Canvas canvas, double x, double y, {required bool sleepy}) {
    if (sleepy) {
      _line(
        canvas,
        Path()
          ..moveTo(x - 29, y)
          ..quadraticBezierTo(x, y + 20, x + 29, y),
        const Color(0xFF163D7A),
        6,
      );
      return;
    }
    final squint = awake && phase > 0.91 && phase < 0.95;
    if (squint) {
      _line(
        canvas,
        Path()
          ..moveTo(x - 27, y)
          ..quadraticBezierTo(x, y + 9, x + 27, y),
        const Color(0xFF163D7A),
        6,
      );
      return;
    }
    _oval(
      canvas,
      Rect.fromCenter(center: Offset(x, y), width: 65, height: 81),
      Colors.white,
    );
    final pupil = Offset(x + gazeX * 10, y + gazeY * 10 + 3);
    _oval(
      canvas,
      Rect.fromCircle(center: pupil, radius: 24),
      const Color(0xFF14ACF0),
    );
    _oval(
      canvas,
      Rect.fromCircle(center: pupil, radius: 17),
      const Color(0xFF122347),
    );
    _oval(
      canvas,
      Rect.fromCircle(center: pupil.translate(-8, -9), radius: 7),
      Colors.white,
    );
    _oval(
      canvas,
      Rect.fromCircle(center: pupil.translate(8, 10), radius: 3),
      Colors.white,
    );
  }

  void _oval(Canvas canvas, Rect rect, Color color) {
    canvas.drawOval(rect, Paint()..color = color);
  }

  void _ovalGradient(Canvas canvas, Rect rect, List<Color> colors) {
    canvas.drawOval(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.42, -0.55),
          radius: 1.35,
          colors: colors,
        ).createShader(rect),
    );
  }

  void _shape(
    Canvas canvas,
    Path path,
    Color color, {
    Color? stroke,
    double width = 1,
  }) {
    canvas.drawPath(path, Paint()..color = color);
    if (stroke != null) _line(canvas, path, stroke, width);
  }

  void _line(Canvas canvas, Path path, Color color, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant JoyfulBlueyPainter old) =>
      gazeX != old.gazeX ||
      gazeY != old.gazeY ||
      talk != old.talk ||
      mood != old.mood ||
      awake != old.awake ||
      tint != old.tint ||
      phase != old.phase;
}
