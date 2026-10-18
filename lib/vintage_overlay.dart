import 'dart:math';
import 'package:flutter/material.dart';
import 'app_theme.dart';

/// Рамка, затемнённые края и роза ветров поверх карты в старинном стиле.
class VintageOverlay extends StatelessWidget {
  final bool vignette;
  final bool compass;
  const VintageOverlay({super.key, required this.vignette, required this.compass});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(children: [
          if (vignette)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.05,
                    colors: [Colors.transparent, Colors.transparent, const Color(0x663A2410)],
                    stops: const [0, 0.62, 1],
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(border: Border.all(color: Pirate.brown, width: 5)),
            ),
          ),
          Positioned.fill(
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: Pirate.gold, width: 1.5)),
            ),
          ),
          if (compass)
            Positioned(
              right: 26,
              bottom: 78,
              child: SizedBox(width: 118, height: 118, child: CustomPaint(painter: _CompassPainter())),
            ),
        ]),
      ),
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final r = s.width / 2 - 16;
    c.drawCircle(ctr, r + 8, Paint()..color = Pirate.parchment.withAlpha(150));
    c.drawCircle(
        ctr, r, Paint()
          ..color = Pirate.brown
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
    c.drawCircle(
        ctr, r * 0.82, Paint()
          ..color = Pirate.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    final dark = Paint()..color = Pirate.brown;
    final light = Paint()..color = Pirate.parchmentDark;
    final edge = Paint()
      ..color = Pirate.brown
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final br = r * 0.2;
    for (var i = 0; i < 8; i++) {
      final a = -pi / 2 + i * pi / 4;
      final len = i.isEven ? r * 0.98 : r * 0.62;
      Offset at(double ang, double d) => ctr + Offset(cos(ang), sin(ang)) * d;
      final tip = at(a, len);
      final left = at(a + pi / 2, br);
      final right = at(a - pi / 2, br);
      final p1 = Path()..moveTo(tip.dx, tip.dy)..lineTo(left.dx, left.dy)..lineTo(ctr.dx, ctr.dy)..close();
      final p2 = Path()..moveTo(tip.dx, tip.dy)..lineTo(right.dx, right.dy)..lineTo(ctr.dx, ctr.dy)..close();
      c.drawPath(p1, dark);
      c.drawPath(p2, light);
      c.drawPath(p1, edge);
      c.drawPath(p2, edge);
    }
    c.drawCircle(ctr, 4, Paint()..color = Pirate.wax);
    final tp = TextPainter(
      text: const TextSpan(text: 'N', style: TextStyle(color: Pirate.wax, fontSize: 17, fontWeight: FontWeight.w800)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(ctr.dx - tp.width / 2, ctr.dy - r - 8 - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
