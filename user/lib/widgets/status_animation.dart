import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Animated status mark — a circle that draws itself, then a ✓ (success) or
/// ✗ (failure) stroked on top, with an elastic pop. Pure CustomPainter, no deps.
///
///   StatusAnimation(success: true)   // green check  → order confirmed
///   StatusAnimation(success: false)  // red cross    → payment cancelled/failed
class StatusAnimation extends StatefulWidget {
  final bool success;
  final double size;
  final Color? color;

  const StatusAnimation({
    super.key,
    required this.success,
    this.size = 72,
    this.color,
  });

  @override
  State<StatusAnimation> createState() => _StatusAnimationState();
}

class _StatusAnimationState extends State<StatusAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _draw;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _scale = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.0, 0.55, curve: Curves.elasticOut),
      ),
    );
    _draw = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.25, 1.0, curve: Curves.easeOutCubic),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ??
        (widget.success ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F));
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        return Transform.scale(
          scale: _scale.value,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _StatusPainter(
              progress: _draw.value,
              success: widget.success,
              color: color,
            ),
          ),
        );
      },
    );
  }
}

class _StatusPainter extends CustomPainter {
  final double progress;
  final bool success;
  final Color color;

  _StatusPainter({
    required this.progress,
    required this.success,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final radius = w / 2 - w * 0.06;
    final stroke = w * 0.085;

    // Soft tinted fill behind the ring.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.10)
        ..style = PaintingStyle.fill,
    );

    final ringPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // Ring draws over the first 55% of progress.
    final ringT = (progress / 0.55).clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * ringT,
      false,
      ringPaint,
    );

    // Mark (check / cross) draws over the remaining 45%.
    final markT = ((progress - 0.55) / 0.45).clamp(0.0, 1.0);
    if (markT <= 0) return;

    final markPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (success) {
      // Check: p1 -> p2 -> p3, drawn progressively by length.
      final p1 = Offset(w * 0.30, h * 0.52);
      final p2 = Offset(w * 0.44, h * 0.66);
      final p3 = Offset(w * 0.72, h * 0.36);
      final seg1 = (p2 - p1).distance;
      final seg2 = (p3 - p2).distance;
      final drawn = markT * (seg1 + seg2);
      final path = Path()..moveTo(p1.dx, p1.dy);
      if (drawn <= seg1) {
        final t = drawn / seg1;
        path.lineTo(p1.dx + (p2.dx - p1.dx) * t, p1.dy + (p2.dy - p1.dy) * t);
      } else {
        path.lineTo(p2.dx, p2.dy);
        final t = ((drawn - seg1) / seg2).clamp(0.0, 1.0);
        path.lineTo(p2.dx + (p3.dx - p2.dx) * t, p2.dy + (p3.dy - p2.dy) * t);
      }
      canvas.drawPath(path, markPaint);
    } else {
      // Cross: first diagonal (0 -> 0.5), then second (0.5 -> 1).
      final a1 = Offset(w * 0.34, h * 0.34);
      final a2 = Offset(w * 0.66, h * 0.66);
      final b1 = Offset(w * 0.66, h * 0.34);
      final b2 = Offset(w * 0.34, h * 0.66);
      final t1 = (markT / 0.5).clamp(0.0, 1.0);
      canvas.drawLine(
        a1,
        Offset(a1.dx + (a2.dx - a1.dx) * t1, a1.dy + (a2.dy - a1.dy) * t1),
        markPaint,
      );
      if (markT > 0.5) {
        final t2 = ((markT - 0.5) / 0.5).clamp(0.0, 1.0);
        canvas.drawLine(
          b1,
          Offset(b1.dx + (b2.dx - b1.dx) * t2, b1.dy + (b2.dy - b1.dy) * t2),
          markPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_StatusPainter old) =>
      old.progress != progress ||
      old.success != success ||
      old.color != color;
}
