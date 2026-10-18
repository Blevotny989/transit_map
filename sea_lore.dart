import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'app_theme.dart';
import 'geo_px.dart';

enum LoreKind { bermuda, serpent, kraken, galleon, ghostShip, whirlpool, atlantis, treasure, label }

/// Морская «пасхалка» на старинной карте: рисунок, подпись и легенда по нажатию.
class LoreItem {
  final String id, title, caption, text;
  final LatLng pos;
  final double widthDeg;
  final LoreKind kind;
  final bool flip;
  const LoreItem(this.id, this.kind, this.pos, this.widthDeg, this.title, this.caption, this.text, {this.flip = false});
}

// Вершины Бермудского треугольника: Майами, Бермуды, Сан-Хуан.
const _bermuda = [LatLng(25.76, -80.19), LatLng(32.30, -64.78), LatLng(18.47, -66.10)];

const loreItems = <LoreItem>[
  LoreItem(
    'bermuda',
    LoreKind.bermuda,
    LatLng(25.5, -70.4),
    16,
    'Бермудский треугольник',
    'Бермудский треугольник',
    'Область Атлантики между Майами, Бермудами и Пуэрто-Рико. Легенды о пропавших здесь кораблях и самолётах '
        'родились в 1950–70-х годах. Береговая охрана США и страховое общество Lloyd\'s не нашли здесь '
        'аварий больше, чем в других оживлённых районах океана: корабли тонут тут как везде, штормов хватает.',
  ),
  LoreItem(
    'leviathan',
    LoreKind.serpent,
    LatLng(26.4, -71.2),
    11,
    'Левиафан',
    'Левиафан',
    'Морское чудовище из Библии (Книга Иова, Псалмы, Исаия). На средневековых картах так рисовали китов, '
        'гигантских змей и вообще всё, что скрывалось в неисследованных глубинах. Если вы дочитали до этого места, '
        'значит, в Бермудском треугольнике вам ничего не угрожает. Почти.',
  ),
  LoreItem(
    'kraken',
    LoreKind.kraken,
    LatLng(63.6, -2.0),
    7,
    'Кракен',
    'Кракен',
    'Скандинавская легенда о гигантском морском существе у берегов Норвегии и Исландии. Его описал епископ '
        'Эрик Понтоппидан в 1750-х годах. Прототипом, вероятно, были гигантские кальмары, которые действительно '
        'существуют и вырастают до 12 метров.',
  ),
  LoreItem(
    'maelstrom',
    LoreKind.whirlpool,
    LatLng(68.4, 8.4),
    4,
    'Мальстрём',
    'Мальстрём',
    'Мощные приливные течения у Лофотенских островов. О них писали Эдгар По («Низвержение в Мальстрём») и '
        'Жюль Верн. На старых картах это был водоворот, который засасывает корабли.',
  ),
  LoreItem(
    'dutchman',
    LoreKind.ghostShip,
    LatLng(-37.5, 14.5),
    8,
    'Летучий голландец',
    'Летучий голландец',
    'Корабль-призрак, который по легенде вечно кружит у мыса Доброй Надежды и не может войти в гавань. '
        'Моряки считали его встречу дурным предзнаменованием.',
  ),
  LoreItem(
    'atlantis',
    LoreKind.atlantis,
    LatLng(33.5, -32.0),
    7,
    'Атлантида',
    'Атлантида',
    'Остров-государство, о котором писал Платон в диалогах «Тимей» и «Критий»: могучая держава, которая ушла '
        'под воду за одни сутки. Историки считают это философской притчей, но искать Атлантиду пытаются до сих пор.',
  ),
  LoreItem(
    'galleon',
    LoreKind.galleon,
    LatLng(-9.0, -132.0),
    9,
    'Манильский галеон',
    'Манильский галеон',
    'Испанские галеоны больше 250 лет ходили через Тихий океан между Манилой и Акапулько и везли серебро, '
        'шёлк и фарфор. Эти корабли были главной мечтой пиратов и английских капёров.',
  ),
  LoreItem(
    'serpent2',
    LoreKind.serpent,
    LatLng(-23.0, 78.0),
    12,
    'Морской змей',
    'Морской змей',
    'Рассказы о гигантских морских змеях известны по всему миру. Скорее всего, за них принимали сельдяных '
        'королей (длиной до 8 метров), обрывки водорослей и стаи дельфинов, идущие в ряд.',
    flip: true,
  ),
  LoreItem(
    'treasure',
    LoreKind.treasure,
    LatLng(14.6, -73.0),
    5,
    'Остров Сокровищ',
    'Остров Сокровищ',
    'Вымышленный остров из романа Роберта Стивенсона (1883). Красный крестик, как и положено, отмечает клад. '
        'Настоящие пираты, кстати, почти не зарывали сокровища: чаще они тратили добычу сразу.',
  ),
  LoreItem(
    'incognita',
    LoreKind.label,
    LatLng(-58.0, -105.0),
    44,
    'Terra Australis Incognita',
    'TERRA AUSTRALIS INCOGNITA',
    'Неизвестная Южная земля. Со времён Птолемея географы были уверены, что на юге должен быть огромный '
        'материк, «уравновешивающий» Северное полушарие. Его рисовали на картах до XVIII века, пока Джеймс Кук '
        'не обошёл Южный океан. Настоящую Антарктиду открыли в 1820 году.',
  ),
  LoreItem(
    'dragons',
    LoreKind.label,
    LatLng(46.0, 98.0),
    24,
    'Hic sunt dracones',
    'HIC SVNT DRACONES',
    '«Здесь водятся драконы». Так подписывали неизвестные земли. Единственная надёжно известная такая '
        'надпись на латыни есть на глобусе Ханта-Ленокса (около 1510 года).',
  ),
];

/// Окно масштабов, в котором видны рисунки, и плавное появление и исчезновение.
double loreAlpha(double zoom) {
  if (zoom < 1.8 || zoom > 7.8) return 0;
  if (zoom < 2.5) return (zoom - 1.8) / 0.7;
  if (zoom > 6.6) return (7.8 - zoom) / 1.2;
  return 1;
}

bool _inTriangle(LatLng p) {
  double sign(LatLng a, LatLng b, LatLng c) =>
      (a.longitude - c.longitude) * (b.latitude - c.latitude) -
      (b.longitude - c.longitude) * (a.latitude - c.latitude);
  final d1 = sign(p, _bermuda[0], _bermuda[1]);
  final d2 = sign(p, _bermuda[1], _bermuda[2]);
  final d3 = sign(p, _bermuda[2], _bermuda[0]);
  final neg = d1 < 0 || d2 < 0 || d3 < 0;
  final pos = d1 > 0 || d2 > 0 || d3 > 0;
  return !(neg && pos);
}

/// Какой рисунок попал под нажатие (null, если никакой).
LoreItem? loreAt(LatLng p, double zoom) {
  if (loreAlpha(zoom) < 0.3) return null;
  LoreItem? best;
  var bd = double.infinity;
  for (final it in loreItems) {
    if (it.kind == LoreKind.bermuda) continue;
    final w = math.min(widthPxOf(it, zoom), 340.0);
    final dx = lonToPx(it.pos.longitude, zoom) - lonToPx(p.longitude, zoom);
    final dy = latToPx(it.pos.latitude, zoom) - latToPx(p.latitude, zoom);
    final d = math.sqrt(dx * dx + dy * dy);
    final r = it.kind == LoreKind.label ? w * 0.5 : w * 0.45;
    if (d <= r && d < bd) {
      bd = d;
      best = it;
    }
  }
  if (best != null) return best;
  if (_inTriangle(p)) return loreItems.first;
  return null;
}

double widthPxOf(LoreItem it, double zoom) => it.widthDeg / 360.0 * worldSize(zoom);

// ------------------------------------------------------------------ рисунки
const _ink = Pirate.ink;
const _paper = Color(0xFFD8C79B);

void _tube(Canvas c, Path p, double w, Color fill, Color line) {
  final o = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = w + 2.2
    ..color = line;
  final i = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = w
    ..color = fill;
  c.drawPath(p, o);
  c.drawPath(p, i);
}

void _along(Path p, double step, void Function(Offset pos, Offset tangent, int i) f) {
  for (final m in p.computeMetrics()) {
    var i = 0;
    for (double d = step / 2; d < m.length; d += step) {
      final t = m.getTangentForOffset(d);
      if (t != null) f(t.position, t.vector, i++);
    }
  }
}

void _waves(Canvas c, double x0, double x1, double y, Color col, {double amp = 1.5, double len = 8}) {
  final p = Path()..moveTo(x0, y);
  var x = x0;
  var up = true;
  while (x < x1) {
    p.quadraticBezierTo(x + len / 2, y + (up ? -amp * 2 : amp * 2), x + len, y);
    x += len;
    up = !up;
  }
  c.drawPath(
      p,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round
        ..color = col);
}

void _dashed(Canvas c, Path p, Paint paint, double dash, double gap) {
  for (final m in p.computeMetrics()) {
    var d = 0.0;
    while (d < m.length) {
      final e = math.min(d + dash, m.length);
      c.drawPath(m.extractPath(d, e), paint);
      d += dash + gap;
    }
  }
}

Paint _line(double w, Color col) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = col;

void _serpent(Canvas c, {bool flip = false}) {
  if (flip) c.scale(-1, 1);
  c.translate(-50, 4);
  _waves(c, 2, 98, 6, Pirate.sea.withAlpha(190));
  final tail = Path()
    ..moveTo(86, 2)
    ..cubicTo(92, -6, 99, -4, 97, 1)
    ..cubicTo(95, 5, 90, 3, 92, -1);
  _tube(c, tail, 3.2, _paper, _ink);
  final humps = <Path>[];
  for (final h in const [
    [26.0, 18.0, 15.0],
    [47.0, 17.0, 13.0],
    [67.0, 16.0, 10.0],
  ]) {
    humps.add(Path()
      ..moveTo(h[0], 3)
      ..cubicTo(h[0], 3 - h[2] * 1.35, h[0] + h[1], 3 - h[2] * 1.35, h[0] + h[1], 3));
  }
  for (final p in humps) {
    _tube(c, p, 5.2, _paper, _ink);
  }
  final hatch = _line(0.7, _ink.withAlpha(150));
  for (final p in humps) {
    _along(p, 3.6, (pos, tan, i) {
      final n = Offset(-tan.dy, tan.dx);
      c.drawLine(pos - n * 1.6, pos + n * 1.6, hatch);
    });
  }
  final neck = Path()
    ..moveTo(24, 4)
    ..cubicTo(19, -8, 24, -20, 14, -24);
  _tube(c, neck, 5.4, _paper, _ink);
  _along(neck, 4.4, (pos, tan, i) {
    var n = Offset(-tan.dy, tan.dx);
    if (n.dx < 0) n = -n;
    final sp = Path()
      ..moveTo(pos.dx, pos.dy)
      ..lineTo(pos.dx + n.dx * 4.2 - tan.dx * 1.6, pos.dy + n.dy * 4.2 - tan.dy * 1.6)
      ..lineTo(pos.dx + tan.dx * 2.2, pos.dy + tan.dy * 2.2)
      ..close();
    c.drawPath(sp, Paint()..color = Pirate.wax);
    c.drawPath(sp, _line(0.6, _ink));
  });
  final fin = Path()
    ..moveTo(16, -27)
    ..quadraticBezierTo(24, -35, 27, -26)
    ..quadraticBezierTo(22, -27, 19, -24)
    ..close();
  c.drawPath(fin, Paint()..color = Pirate.wax.withAlpha(200));
  c.drawPath(fin, _line(0.9, _ink));
  final head = Path()
    ..moveTo(19, -28)
    ..quadraticBezierTo(9, -33, -1, -25)
    ..quadraticBezierTo(5, -21, 11, -20)
    ..quadraticBezierTo(16, -19, 19, -21)
    ..close();
  c.drawPath(head, Paint()..color = _paper);
  c.drawPath(head, _line(1.3, _ink));
  c.drawCircle(const Offset(10, -26), 1.9, Paint()..color = Colors.white);
  c.drawCircle(const Offset(9.6, -26), 0.9, Paint()..color = _ink);
  c.drawLine(const Offset(7.2, -29.2), const Offset(12.8, -27.6), _line(1.1, _ink));
  c.drawLine(const Offset(-0.5, -23.4), const Offset(14, -22.2), _line(0.8, _ink));
  for (var k = 0; k < 4; k++) {
    final x = 1.5 + k * 3.2;
    final y = -23.2 + k * 0.35;
    final t = Path()
      ..moveTo(x, y)
      ..lineTo(x + 1.4, y + 0.1)
      ..lineTo(x + 0.7, y + 2.2)
      ..close();
    c.drawPath(t, Paint()..color = Colors.white);
    c.drawPath(t, _line(0.4, _ink));
  }
  final tongue = Path()
    ..moveTo(-1, -23)
    ..lineTo(-6, -22)
    ..moveTo(-6, -22)
    ..lineTo(-9.5, -24.5)
    ..moveTo(-6, -22)
    ..lineTo(-9.5, -19.5);
  c.drawPath(tongue, _line(1.0, Pirate.wax));
}

void _kraken(Canvas c) {
  c.translate(-50, -6);
  _waves(c, 0, 100, 44, Pirate.sea.withAlpha(190));
  const fill = Color(0xFFD7B89A);
  for (var k = 0; k < 8; k++) {
    final side = k < 4 ? -1.0 : 1.0;
    final sx = 50 + (k - 3.5) * 4.5;
    final dx = (k - 3.5) * 9.5;
    final ex = sx + dx * 1.5;
    final ey = 40 - (k.isEven ? 22.0 : 8.0);
    final t = Path()
      ..moveTo(sx, 40)
      ..cubicTo(sx + dx * 0.4, 56, sx + dx * 1.2, 52, ex, ey)
      ..cubicTo(ex + side * 5, ey - 6, ex + side * 8, ey + 2, ex + side * 3, ey + 3);
    _tube(c, t, 3.6, fill, _ink);
    final dot = Paint()..color = _ink.withAlpha(170);
    _along(t, 5.2, (pos, tan, i) => c.drawCircle(pos, 0.7, dot));
  }
  final mantle = Path()
    ..moveTo(50, 0)
    ..cubicTo(76, 4, 72, 30, 62, 42)
    ..lineTo(38, 42)
    ..cubicTo(28, 30, 24, 4, 50, 0)
    ..close();
  c.drawPath(mantle, Paint()..color = fill);
  c.drawPath(mantle, _line(1.5, _ink));
  final fin = Path()
    ..moveTo(50, 0)
    ..quadraticBezierTo(40, -10, 32, -2)
    ..quadraticBezierTo(40, -2, 44, 6)
    ..moveTo(50, 0)
    ..quadraticBezierTo(60, -10, 68, -2)
    ..quadraticBezierTo(60, -2, 56, 6);
  c.drawPath(fin, _line(1.3, _ink));
  for (final ex in const [41.0, 59.0]) {
    c.drawCircle(Offset(ex, 29), 4.6, Paint()..color = Colors.white);
    c.drawCircle(Offset(ex, 29), 4.6, _line(1.0, _ink));
    c.drawOval(Rect.fromCenter(center: Offset(ex, 29), width: 1.8, height: 6), Paint()..color = _ink);
  }
  c.drawLine(const Offset(36, 22), const Offset(46, 25), _line(1.5, _ink));
  c.drawLine(const Offset(64, 22), const Offset(54, 25), _line(1.5, _ink));
  for (var k = 0; k < 6; k++) {
    c.drawLine(Offset(34 + k * 6.4, 12 + (k % 2) * 4), Offset(36 + k * 6.4, 16 + (k % 2) * 4), _line(0.7, _ink.withAlpha(130)));
  }
  // маленький кораблик в щупальцах
  c.save();
  c.translate(88, 6);
  c.rotate(-0.55);
  c.scale(0.3, 0.3);
  _shipBody(c, ghost: false);
  c.restore();
}

/// Галеон в координатах 0..100 x 0..90, ватерлиния около y = 78.
void _shipBody(Canvas c, {required bool ghost}) {
  final hullFill = ghost ? const Color(0xFF3F5A55) : const Color(0xFF8A6038);
  final sailFill = ghost ? const Color(0xB8BFE3D0) : const Color(0xFFF3E7C6);
  final hull = Path()
    ..moveTo(10, 58)
    ..lineTo(90, 58)
    ..quadraticBezierTo(82, 77, 60, 79)
    ..lineTo(34, 79)
    ..quadraticBezierTo(16, 74, 10, 58)
    ..close();
  final castle = Path()
    ..moveTo(74, 58)
    ..lineTo(74, 46)
    ..lineTo(92, 46)
    ..lineTo(90, 58)
    ..close();
  for (final x in const [30.0, 50.0, 70.0]) {
    final top = x == 50.0 ? 4.0 : 12.0;
    c.drawLine(Offset(x, 58), Offset(x, top), _line(1.6, _ink));
  }
  c.drawLine(const Offset(12, 58), const Offset(-4, 48), _line(1.6, _ink));
  for (final m in const [
    [30.0, 14.0, 34.0, 11.0],
    [50.0, 6.0, 30.0, 14.0],
    [70.0, 14.0, 34.0, 11.0],
  ]) {
    final x = m[0], y1 = m[1], y2 = m[2], hw = m[3] + 4;
    final sail = Path()
      ..moveTo(x - hw, y1)
      ..quadraticBezierTo(x, y1 + 5, x + hw, y1)
      ..lineTo(x + hw - 1, y2);
    if (ghost) {
      // рваный нижний край
      for (var k = 0; k < 6; k++) {
        sail.lineTo(x + hw - 1 - (k + 1) * (2 * hw - 2) / 6, y2 + (k.isEven ? 3.5 : -1));
      }
      sail.close();
    } else {
      sail
        ..quadraticBezierTo(x, y2 + 6, x - hw + 1, y2)
        ..close();
    }
    c.drawPath(sail, Paint()..color = sailFill);
    c.drawPath(sail, _line(1.0, _ink));
  }
  if (!ghost) {
    final mid = _line(1.8, Pirate.wax);
    c.drawLine(const Offset(46, 12), const Offset(54, 22), mid);
    c.drawLine(const Offset(54, 12), const Offset(46, 22), mid);
  }
  c.drawPath(castle, Paint()..color = hullFill);
  c.drawPath(castle, _line(1.2, _ink));
  c.drawPath(hull, Paint()..color = hullFill);
  c.drawPath(hull, _line(1.4, _ink));
  for (final y in const [63.0, 69.0]) {
    c.drawLine(Offset(14 + (y - 58) * 0.2, y), Offset(88 - (y - 58) * 0.5, y), _line(0.7, _ink.withAlpha(150)));
  }
  for (var k = 0; k < 4; k++) {
    c.drawCircle(Offset(36 + k * 12, 66), 1.1, Paint()..color = _ink);
  }
  final flag = Path()
    ..moveTo(50, 4)
    ..lineTo(62, 1)
    ..lineTo(57, 5)
    ..lineTo(62, 9)
    ..lineTo(50, 7)
    ..close();
  c.drawPath(flag, Paint()..color = ghost ? const Color(0xFF9CC9B0) : Pirate.wax);
  c.drawPath(flag, _line(0.7, _ink));
}

void _ship(Canvas c, {required bool ghost}) {
  c.translate(-50, -50);
  if (ghost) {
    c.drawCircle(
        const Offset(50, 42),
        62,
        Paint()
          ..shader = const RadialGradient(colors: [Color(0x663DDC97), Color(0x003DDC97)])
              .createShader(Rect.fromCircle(center: const Offset(50, 42), radius: 62)));
  }
  _shipBody(c, ghost: ghost);
  _waves(c, 0, 100, 78, Pirate.sea.withAlpha(200), amp: 1.8, len: 9);
  _waves(c, 6, 94, 85, Pirate.sea.withAlpha(140), amp: 1.4, len: 8);
}

void _whirl(Canvas c) {
  final p = _line(1.2, Pirate.sea.withAlpha(230));
  for (var arm = 0; arm < 3; arm++) {
    final path = Path();
    var first = true;
    for (double t = 0; t < 5.2; t += 0.15) {
      final r = 2 + t * 8.2;
      final a = t * 1.15 + arm * 2.094;
      final pt = Offset(math.cos(a) * r, math.sin(a) * r * 0.42);
      if (first) {
        path.moveTo(pt.dx, pt.dy);
        first = false;
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    c.drawPath(path, p);
  }
  c.drawOval(Rect.fromCenter(center: Offset.zero, width: 8, height: 3), Paint()..color = _ink);
}

void _atlantis(Canvas c) {
  c.translate(0, -4);
  const stone = Color(0xFFE9DDBB);
  final stroke = _line(1.1, _ink);
  const hs = [26.0, 30.0, 22.0, 30.0, 14.0];
  for (var k = 0; k < 5; k++) {
    final x = -24.0 + k * 12;
    final r = Rect.fromLTWH(x - 2.4, 16 - hs[k], 4.8, hs[k]);
    c.drawRect(r, Paint()..color = stone);
    c.drawRect(r, stroke);
    c.drawRect(Rect.fromLTWH(x - 3.4, 16 - hs[k] - 1.6, 6.8, 2), Paint()..color = stone);
  }
  final base = Rect.fromLTWH(-31, 16, 62, 4);
  c.drawRect(base, Paint()..color = stone);
  c.drawRect(base, stroke);
  final beam = Rect.fromLTWH(-30, -16, 44, 4);
  c.drawRect(beam, Paint()..color = stone);
  c.drawRect(beam, stroke);
  final ped = Path()
    ..moveTo(-31, -16)
    ..lineTo(-8, -29)
    ..lineTo(15, -16)
    ..close();
  c.drawPath(ped, Paint()..color = stone);
  c.drawPath(ped, stroke);
  // вода поверх нижней части: храм наполовину затоплен
  c.drawRect(const Rect.fromLTWH(-62, 2, 124, 42), Paint()..color = Pirate.sea.withAlpha(105));
  _waves(c, -62, 62, 2, Pirate.sea.withAlpha(230), amp: 1.6, len: 8);
  _waves(c, -58, 58, 10, Pirate.sea.withAlpha(150), amp: 1.3, len: 7);
  for (final b in const [Offset(-14, -2), Offset(18, -6), Offset(-4, -12)]) {
    c.drawCircle(b + const Offset(0, 18), 1.2, _line(0.6, Pirate.sea));
  }
}

void _treasure(Canvas c) {
  c.translate(0, 6);
  _waves(c, -50, 50, 16, Pirate.sea.withAlpha(190));
  final island = Path()
    ..moveTo(-30, 12)
    ..quadraticBezierTo(-24, -4, -6, -2)
    ..quadraticBezierTo(8, -8, 22, 0)
    ..quadraticBezierTo(34, 6, 30, 12)
    ..close();
  c.drawPath(island, Paint()..color = const Color(0xFFE5D2A0));
  c.drawPath(island, _line(1.3, _ink));
  final dot = Paint()..color = _ink.withAlpha(110);
  for (var k = 0; k < 14; k++) {
    c.drawCircle(Offset(-24 + k * 3.9, 6 + (k % 3) * 2.2), 0.55, dot);
  }
  final trunk = Path()
    ..moveTo(10, -2)
    ..quadraticBezierTo(14, -14, 11, -26);
  c.drawPath(trunk, _line(2.2, const Color(0xFF6B4A24)));
  final leaf = _line(1.6, const Color(0xFF4E6B3A));
  for (final e in const [Offset(-4, -22), Offset(4, -32), Offset(22, -30), Offset(26, -21), Offset(11, -18)]) {
    final lp = Path()
      ..moveTo(11, -26)
      ..quadraticBezierTo((11 + e.dx) / 2, e.dy - 6, e.dx, e.dy);
    c.drawPath(lp, leaf);
  }
  final x = _line(2.4, Pirate.wax);
  c.drawLine(const Offset(-17, 0), const Offset(-9, 8), x);
  c.drawLine(const Offset(-9, 0), const Offset(-17, 8), x);
  final trail = Path()
    ..moveTo(-52, 22)
    ..quadraticBezierTo(-40, 6, -33, 14)
    ..quadraticBezierTo(-26, 20, -18, 10)
    ..quadraticBezierTo(-14, 8, -13, 4);
  _dashed(c, trail, _line(1.0, _ink), 3.2, 2.6);
}

TextPainter _text(String s, TextStyle base, double size, Color color, {bool halo = false, double maxWidth = 600}) {
  final style = halo
      ? base.copyWith(
          fontSize: size,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = size * 0.28
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0xFFF3E4C0))
      : base.copyWith(fontSize: size, color: color);
  return TextPainter(
    text: TextSpan(text: s, style: style),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout(maxWidth: maxWidth);
}

void _caption(Canvas c, String s, Offset center, double size, TextStyle base, {Color color = _ink, double maxWidth = 600}) {
  final back = _text(s, base, size, color, halo: true, maxWidth: maxWidth);
  final front = _text(s, base, size, color, maxWidth: maxWidth);
  final o = center - Offset(front.width / 2, front.height / 2);
  back.paint(c, o);
  front.paint(c, o);
}

/// Румбы: тонкие лучи из нескольких «роз ветров», как на портоланах.
class RhumbData {
  static const anchors = [LatLng(28, -42), LatLng(-18, 72), LatLng(8, -140), LatLng(46, 160)];
}

class SeaLorePainter extends CustomPainter {
  SeaLorePainter({required this.center, required this.zoom, required this.label});
  final LatLng center;
  final double zoom;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = loreAlpha(zoom);
    if (alpha <= 0) return;
    final cx = lonToPx(center.longitude, zoom), cy = latToPx(center.latitude, zoom);
    final hw = size.width / 2, hh = size.height / 2;
    Offset toScreen(LatLng p) => Offset(lonToPx(p.longitude, zoom) - cx + hw, latToPx(p.latitude, zoom) - cy + hh);

    // румбы
    final a8 = (alpha * 60).round();
    final rp = _line(0.8, _ink.withAlpha(a8));
    final len = worldSize(zoom) * 0.34;
    for (final a in RhumbData.anchors) {
      final o = toScreen(a);
      if (o.dx < -len || o.dx > size.width + len || o.dy < -len || o.dy > size.height + len) continue;
      for (var k = 0; k < 16; k++) {
        final ang = k * math.pi / 8;
        canvas.drawLine(o, o + Offset(math.sin(ang), -math.cos(ang)) * len, rp);
      }
      canvas.drawCircle(o, len * 0.035, _line(1.0, _ink.withAlpha(a8 + 20)));
    }

    // Бермудский треугольник
    final tri = Path();
    for (var i = 0; i < _bermuda.length; i++) {
      final o = toScreen(_bermuda[i]);
      if (i == 0) {
        tri.moveTo(o.dx, o.dy);
      } else {
        tri.lineTo(o.dx, o.dy);
      }
    }
    tri.close();
    final needLayer = alpha < 0.99;
    if (needLayer) {
      canvas.saveLayer(null, Paint()..color = Color.fromARGB((alpha * 255).round(), 255, 255, 255));
    }
    canvas.drawPath(tri, Paint()..color = const Color(0x24B71C1C));
    final tw = math.max(1.4, zoom * 0.45);
    _dashed(canvas, tri, _line(tw, Pirate.wax.withAlpha(230)), tw * 5, tw * 3.2);

    for (final it in loreItems) {
      if (it.kind == LoreKind.bermuda) continue;
      final w = math.min(widthPxOf(it, zoom), 340.0);
      if (w < 16) continue;
      final o = toScreen(it.pos);
      if (o.dx < -w || o.dx > size.width + w || o.dy < -w || o.dy > size.height + w) continue;
      if (it.kind != LoreKind.label) {
        canvas.save();
        canvas.translate(o.dx, o.dy);
        final sc = w / 100.0;
        canvas.scale(sc, sc);
        switch (it.kind) {
          case LoreKind.serpent:
            _serpent(canvas, flip: it.flip);
          case LoreKind.kraken:
            _kraken(canvas);
          case LoreKind.galleon:
            _ship(canvas, ghost: false);
          case LoreKind.ghostShip:
            _ship(canvas, ghost: true);
          case LoreKind.whirlpool:
            _whirl(canvas);
          case LoreKind.atlantis:
            _atlantis(canvas);
          case LoreKind.treasure:
            _treasure(canvas);
          case LoreKind.bermuda || LoreKind.label:
            break;
        }
        canvas.restore();
      }
      final fs = it.kind == LoreKind.label ? (w * 0.07).clamp(10.0, 26.0).toDouble() : (w * 0.12).clamp(9.0, 20.0).toDouble();
      final dy = it.kind == LoreKind.label ? 0.0 : w * 0.42;
      _caption(canvas, it.caption, o + Offset(0, dy), fs, label, color: it.kind == LoreKind.label ? _ink.withAlpha(200) : _ink, maxWidth: w * 1.6 + 60);
    }

    // подпись треугольника
    final ctr = toScreen(loreItems.first.pos);
    final tw2 = widthPxOf(loreItems.first, zoom);
    if (tw2 > 40) {
      _caption(canvas, loreItems.first.caption, ctr + Offset(0, tw2 * 0.55), (tw2 * 0.085).clamp(10.0, 22.0).toDouble(), label,
          color: Pirate.wax, maxWidth: tw2 * 2);
      for (final v in _bermuda) {
        final o = toScreen(v);
        _caption(canvas, '☠', o, (tw2 * 0.07).clamp(9.0, 20.0).toDouble(), label, color: Pirate.wax);
      }
    }
    if (needLayer) canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SeaLorePainter old) => true;
}

/// Слой морских легенд поверх старинной карты.
class SeaLoreLayer extends StatelessWidget {
  const SeaLoreLayer({super.key, required this.label});
  final TextStyle label;

  @override
  Widget build(BuildContext context) {
    final cam = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(size: Size.infinite, painter: SeaLorePainter(center: cam.center, zoom: cam.zoom, label: label)),
    );
  }
}
