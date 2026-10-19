import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'boot.dart';
import 'config.dart';
import 'map_screen.dart';
import 'tile_cache.dart';

/// Приветственный экран: пока открывается кэш, определяется положение и загружается карта,
/// карта уже строится под ним и появляется сразу готовой.
class BootGate extends StatefulWidget {
  const BootGate({super.key});
  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> with SingleTickerProviderStateMixin {
  bool _ready = false, _hide = false, _gone = false;
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 16))..repeat();
  final DateTime _t0 = DateTime.now();
  static const _minShow = Duration(milliseconds: 1600);
  static const _tips = [
    'Правый клик по карте: поставить точку «куда ехать».',
    'Просмотренные места сохраняются на диске и открываются без интернета.',
    'В настройках (значок шестерёнки) можно выбрать язык названий и старинную карту.',
    'Нажмите на остановку, чтобы увидеть маршруты, которые через неё проходят.',
    'На старинной карте в океанах живут чудовища. Нажмите на любое из них.',
  ];
  late final String _tip = _tips[math.Random().nextInt(_tips.length)];

  @override
  void initState() {
    super.initState();
    Boot.ready.addListener(_finish);
    Future<void>.delayed(const Duration(seconds: 8), _finish);
    _init();
  }

  Future<void> _init() async {
    Boot.set('Открываю кэш карты…');
    await initTileCache();
    if (!mounted) return;
    Boot.set('Строю карту…');
    setState(() => _ready = true);
  }

  void _finish() {
    if (!mounted || _hide) return;
    if (!Boot.ready.value && DateTime.now().difference(_t0) < const Duration(seconds: 8)) return;
    final left = _minShow - DateTime.now().difference(_t0);
    if (left > Duration.zero) {
      Future<void>.delayed(left, _finish);
      return;
    }
    setState(() => _hide = true);
  }

  @override
  void dispose() {
    Boot.ready.removeListener(_finish);
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pirate = Config.pirate;
    final bg = pirate
        ? const [Color(0xFFF3E4C0), Color(0xFFE0C58F)]
        : const [Color(0xFF0D2B5C), Color(0xFF1E6FD9)];
    final fg = pirate ? const Color(0xFF3A2410) : Colors.white;
    return Stack(fit: StackFit.expand, children: [
      if (_ready) const MapScreen(),
      if (!_gone)
        IgnorePointer(
          ignoring: _hide,
          child: AnimatedOpacity(
            opacity: _hide ? 0 : 1,
            duration: const Duration(milliseconds: 600),
            onEnd: () {
              if (_hide && mounted) setState(() => _gone = true);
            },
            child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: bg)),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: AnimatedBuilder(
                      animation: _spin,
                      builder: (_, __) => CustomPaint(painter: _LogoPainter(_spin.value, pirate)),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text('Добро пожаловать!',
                      style: TextStyle(color: fg, fontSize: 34, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
                  const SizedBox(height: 6),
                  Text(pirate ? 'Поднимаем паруса и разворачиваем карту…' : 'Транспортная карта: остановки, маршруты, погода',
                      style: TextStyle(color: fg.withAlpha(210), fontSize: 16, decoration: TextDecoration.none)),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: 280,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        color: pirate ? const Color(0xFF9C2F1F) : Colors.white,
                        backgroundColor: fg.withAlpha(50),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: Boot.stage,
                    builder: (_, s, __) => Text(s,
                        style: TextStyle(color: fg.withAlpha(230), fontSize: 14, decoration: TextDecoration.none)),
                  ),
                  const SizedBox(height: 34),
                  SizedBox(
                    width: 420,
                    child: Text(_tip,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: fg.withAlpha(170), fontSize: 13, decoration: TextDecoration.none)),
                  ),
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _LogoPainter extends CustomPainter {
  _LogoPainter(this.t, this.pirate);
  final double t;
  final bool pirate;

  @override
  void paint(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final col = pirate ? const Color(0xFF5B3A1A) : Colors.white;
    final acc = pirate ? const Color(0xFF9C2F1F) : const Color(0xFFFFC107);
    c.drawCircle(ctr, 66, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = col);
    c.drawCircle(ctr, 56, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = col.withAlpha(150));
    // вращающаяся стрелка компаса
    c.save();
    c.translate(ctr.dx, ctr.dy);
    c.rotate(t * 2 * math.pi);
    final n = Path()..moveTo(0, -54)..lineTo(9, 0)..lineTo(-9, 0)..close();
    final so = Path()..moveTo(0, 54)..lineTo(9, 0)..lineTo(-9, 0)..close();
    c.drawPath(n, Paint()..color = acc);
    c.drawPath(so, Paint()..color = col.withAlpha(200));
    c.restore();
    c.drawCircle(ctr, 6, Paint()..color = col);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final o1 = ctr + Offset(math.cos(a), math.sin(a)) * 66;
      final o2 = ctr + Offset(math.cos(a), math.sin(a)) * (i % 3 == 0 ? 74 : 70);
      c.drawLine(o1, o2, Paint()..color = col..strokeWidth = 2);
    }
  }

  @override
  bool shouldRepaint(covariant _LogoPainter old) => old.t != t;
}
