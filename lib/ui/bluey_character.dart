import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../link/models.dart';
import 'joyful_bluey_painter.dart';

/// Renderer selection is deliberately local until a licensed Rive asset and
/// runtime have passed platform validation.
enum FaceRenderer { native, rive }

/// No Rive runtime is bundled. Every request resolves to the native painter.
FaceRenderer resolveFaceRenderer(FaceRenderer requested) => FaceRenderer.native;

/// Scalable character artwork shared by the Mac, iOS and Android Flutter UI.
///
/// The painter uses a fixed design space and has no image/network dependency.
/// Frame inputs are captured as primitives so mutable FaceState updates repaint.
class BlueyCharacter extends StatelessWidget {
  const BlueyCharacter({
    super.key,
    required this.face,
    required this.awake,
    required this.tint,
    this.phase = 0,
    this.requestedRenderer = FaceRenderer.native,
    this.legacyArtwork = false,
  });

  final FaceRenderer requestedRenderer;

  /// Retains pre-refresh reference screenshots without affecting production.
  final bool legacyArtwork;
  final FaceState face;
  final bool awake;
  final Color tint;

  /// Normalized, deterministic animation phase in [0, 1].
  final double phase;

  @override
  Widget build(BuildContext context) {
    assert(resolveFaceRenderer(requestedRenderer) == FaceRenderer.native);
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final effectivePhase = reducedMotion ? 0.0 : phase;
    return RepaintBoundary(
      child: CustomPaint(
        painter: legacyArtwork
            ? _BlueyPainter(
                gazeX: _bounded(face.gazeX, -1, 1),
                gazeY: _bounded(face.gazeY, -1, 1),
                talk: _bounded(face.talk, 0, 1),
                mood: face.mood,
                awake: awake,
                tint: tint,
                phase: _bounded(effectivePhase, 0, 1),
              )
            : JoyfulBlueyPainter(
                gazeX: _bounded(face.gazeX, -1, 1),
                gazeY: _bounded(face.gazeY, -1, 1),
                talk: _bounded(face.talk, 0, 1),
                mood: face.mood,
                awake: awake,
                tint: tint,
                phase: _bounded(effectivePhase, 0, 1),
              ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

double _bounded(double value, double min, double max) =>
    value.isFinite ? value.clamp(min, max).toDouble() : 0;

class _BlueyPainter extends CustomPainter {
  const _BlueyPainter({
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

    final breath = awake ? math.sin(phase * 2 * math.pi) * 2 : 0.0;
    canvas.translate(0, breath);
    final outline = Paint()..color = const Color(0xFF153A72);
    final body = Rect.fromCircle(center: const Offset(160, 173), radius: 125);

    // Two small leaves form Bluey's signature top tuft.
    final tuft = Path()
      ..moveTo(155, 58)
      ..quadraticBezierTo(130, 31, 137, 15)
      ..quadraticBezierTo(160, 23, 165, 51)
      ..quadraticBezierTo(177, 21, 198, 24)
      ..quadraticBezierTo(194, 46, 174, 62)
      ..close();
    canvas.drawPath(tuft, Paint()..color = const Color(0xFF397DB1));
    canvas.drawPath(
      tuft,
      Paint()
        ..color = const Color(0xFF174E84)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    canvas.drawOval(body, outline);
    canvas.drawOval(
      body.deflate(3),
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.55),
          radius: 1.3,
          colors: [
            Color.lerp(const Color(0xFF85DEFF), tint, 0.24)!,
            Color.lerp(const Color(0xFF459CEB), tint, 0.24)!,
            const Color(0xFF20559B),
          ],
          stops: const [0, 0.60, 1],
        ).createShader(body),
    );
    canvas.drawOval(
      const Rect.fromLTWH(69, 64, 146, 63),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );

    final sleepy = !awake || mood == Mood.sleepy || mood == Mood.resting;
    final happy = mood == Mood.happy;
    final thinking = mood == Mood.thinking;

    // Soft cheek highlights and expressive eyebrows.
    for (final x in <double>[91, 229]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(x, 213), width: 33, height: 19),
        Paint()
          ..color = const Color(0xFFF69AAA)
              .withValues(alpha: sleepy ? 0.13 : 0.46),
      );
    }
    _stroke(
      canvas,
      Path()
        ..moveTo(92, thinking ? 118 : 112)
        ..quadraticBezierTo(114, thinking ? 100 : 91, 135, 111),
      const Color(0xFF133F7C),
      7,
    );
    _stroke(
      canvas,
      Path()
        ..moveTo(185, 111)
        ..quadraticBezierTo(205, happy ? 86 : 92, 228, thinking ? 119 : 112),
      const Color(0xFF133F7C),
      7,
    );

    for (final x in <double>[116, 204]) {
      final eye = Rect.fromCenter(
        center: Offset(x, 158),
        width: 72,
        height: sleepy ? 37 : 88,
      );
      canvas.drawOval(eye, Paint()..color = const Color(0xFFF6FBFF));
      canvas.drawOval(
        eye,
        Paint()
          ..color = const Color(0xFF2F68A3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
      if (!sleepy) {
        final pupil = Offset(x + gazeX * 14, 161 + gazeY * 13);
        canvas.drawCircle(pupil, 18, Paint()..color = const Color(0xFF172F58));
        canvas.drawCircle(
          pupil.translate(-6, -7),
          6,
          Paint()..color = Colors.white,
        );
      } else {
        _stroke(
          canvas,
          Path()
            ..moveTo(x - 29, 160)
            ..quadraticBezierTo(x, 175, x + 29, 160),
          const Color(0xFF164579),
          5,
        );
      }
    }

    if (mood == Mood.talking && talk > 0.10 && awake) {
      canvas.drawOval(
        Rect.fromCenter(
          center: const Offset(160, 238),
          width: 34 + talk * 11,
          height: 15 + talk * 30,
        ),
        Paint()..color = const Color(0xFF182B50),
      );
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(160, 245 + talk * 4),
          width: 22,
          height: 8,
        ),
        Paint()..color = const Color(0xFFED829A),
      );
    } else {
      _stroke(
        canvas,
        Path()
          ..moveTo(137, 231)
          ..quadraticBezierTo(160, happy ? 260 : 244, 183, 231),
        const Color(0xFF163966),
        6,
      );
    }

    if (!awake) {
      canvas.drawOval(
        body.deflate(4),
        Paint()..color = const Color(0xFF071832).withValues(alpha: 0.16),
      );
    }
    canvas.restore();
  }

  void _stroke(Canvas canvas, Path path, Color color, double width) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BlueyPainter old) =>
      gazeX != old.gazeX ||
      gazeY != old.gazeY ||
      talk != old.talk ||
      mood != old.mood ||
      awake != old.awake ||
      tint != old.tint ||
      phase != old.phase;
}
