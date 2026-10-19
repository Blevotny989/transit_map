import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'app_theme.dart';

Future<ui.Image>? _grain;

/// Бумажная фактура: мелкие пятнышки и волокна. Создаётся один раз.
Future<ui.Image> _makeGrain() async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(const Rect.fromLTWH(0, 0, 256, 256), Paint()..color = Colors.white);
  final rnd = Random(7);
  final p = Paint();
  for (var i = 0; i < 2800; i++) {
    p.color = Color.fromARGB(rnd.nextInt(30) + 8, 96, 64, 24);
    c.drawCircle(Offset(rnd.nextDouble() * 256, rnd.nextDouble() * 256), rnd.nextDouble() * 1.3 + 0.3, p);
  }
  final f = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.6
    ..color = const Color(0x1E6E5028);
  for (var i = 0; i < 160; i++) {
    final x = rnd.nextDouble() * 256, y = rnd.nextDouble() * 256;
    c.drawPath(
        Path()
          ..moveTo(x, y)
          ..quadraticBezierTo(x + rnd.nextDouble() * 14 - 7, y + rnd.nextDouble() * 14 - 7, x + rnd.nextDouble() * 18 - 9,
              y + rnd.nextDouble() * 18 - 9),
        f);
  }
  return rec.endRecording().toImage(256, 256);
}

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.img);
  final ui.Image img;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    canvas.drawRect(
        r,
        Paint()
          ..shader = ImageShader(img, TileMode.repeated, TileMode.repeated, Matrix4.identity().storage)
          ..blendMode = BlendMode.multiply);
    // пятна времени
    final spots = [
      [0.18, 0.22, 0.20],
      [0.78, 0.18, 0.16],
      [0.62, 0.76, 0.22],
      [0.12, 0.82, 0.15],
    ];
    for (final s in spots) {
      final ctr = Offset(size.width * s[0], size.height * s[1]);
      final rad = size.shortestSide * s[2];
      canvas.drawCircle(
          ctr,
          rad,
          Paint()
            ..shader = const RadialGradient(colors: [Color(0x228A5A1E), Color(0x00000000)])
                .createShader(Rect.fromCircle(center: ctr, radius: rad)));
    }
  }

  @override
  bool shouldRepaint(covariant _PaperPainter old) => old.img != img;
}

/// Рамка, затемнённые края, бумажная фактура и роза ветров поверх карты в старинном стиле.
class VintageOverlay extends StatelessWidget {
  final bool vignette;
  final bool compass;
  final bool paper;
  const VintageOverlay({super.key, required this.vignette, required this.compass, this.paper = false});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(children: [
          if (paper)
            Positioned.fill(
              child: FutureBuilder<ui.Image>(
                future: _grain ??= _makeGrain(),
                builder: (_, snap) => snap.hasData
                    ? RepaintBoundary(child: CustomPaint(painter: _PaperPainter(snap.data!)))
                    : const SizedBox.shrink(),
              ),
            ),
          if (vignette)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 1.1,
                    colors: [Colors.transparent, Colors.transparent, const Color(0x553A2410)],
                    stops: const [0, 0.68, 1],
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
