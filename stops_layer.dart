import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'app_theme.dart';
import 'config.dart';
import 'geo_px.dart';
import 'models.dart';
import 'services.dart';

/// Что рисовать на экране при данном масштабе.
class MapObjects {
  final List<Stop> stops;
  final List<PlaceDot> dots;
  const MapObjects(this.stops, this.dots);
}

MapObjects selectObjects(LatLngBounds b, double z, Set<StopKind> kinds) {
  var stops = <Stop>[];
  var dots = <PlaceDot>[];
  if (z >= Config.minStopsZoom) {
    stops = stopStore.visible(b, max: 900).where((s) => kinds.contains(s.kind)).toList();
  } else {
    if (z >= Config.minStationsZoom) {
      stops = stationStore.visible(b, max: 300).where((s) => kinds.contains(s.kind)).toList();
    }
    if (z >= 8) {
      dots = bigPlaceStore.visible(b, max: 400);
      if (z >= 10) {
        dots = [
          ...dots,
          ...smallPlaceStore.visible(b, max: 500).where((d) => z >= 12 || d.kind == 'village'),
        ];
      }
    }
  }
  return MapObjects(stops, dots);
}

LatLngBounds _around(LatLng p, double zoom, double radiusPx) {
  final d = radiusPx * 360.0 / worldSize(zoom);
  return LatLngBounds(LatLng(p.latitude - d, p.longitude - d), LatLng(p.latitude + d, p.longitude + d));
}

double _distPx(LatLng a, LatLng b, double zoom) {
  final dx = lonToPx(a.longitude, zoom) - lonToPx(b.longitude, zoom);
  final dy = latToPx(a.latitude, zoom) - latToPx(b.latitude, zoom);
  return math.sqrt(dx * dx + dy * dy);
}

/// Остановка под точкой нажатия (в радиусе [radiusPx] пикселей).
Stop? stopAt(LatLng p, double zoom, Set<StopKind> kinds, {double radiusPx = 16}) {
  final objs = selectObjects(_around(p, zoom, radiusPx), zoom, kinds);
  Stop? best;
  var bd = radiusPx;
  for (final s in objs.stops) {
    final d = _distPx(s.pos, p, zoom);
    if (d <= bd) {
      bd = d;
      best = s;
    }
  }
  return best;
}

/// Город или посёлок под точкой нажатия.
PlaceDot? dotAt(LatLng p, double zoom, Set<StopKind> kinds, {double radiusPx = 14}) {
  final objs = selectObjects(_around(p, zoom, radiusPx), zoom, kinds);
  PlaceDot? best;
  var bd = radiusPx;
  for (final s in objs.dots) {
    final d = _distPx(s.pos, p, zoom);
    if (d <= bd) {
      bd = d;
      best = s;
    }
  }
  return best;
}

final Map<String, ui.Picture> _sprites = {};
final Map<String, TextPainter> _labels = {};

ui.Picture _sprite(StopKind k, double size, bool ink) {
  final key = '${k.index}_${size.round()}_${ink ? 1 : 0}';
  return _sprites.putIfAbsent(key, () {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final r = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: size, height: size), Radius.circular(size * 0.3));
    c.drawRRect(r, Paint()..color = k.color);
    c.drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = ink ? Pirate.gold : Colors.white);
    final ic = k.icon;
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(ic.codePoint),
        style: TextStyle(fontFamily: ic.fontFamily, package: ic.fontPackage, fontSize: size * 0.62, color: Colors.white),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(-tp.width / 2, -tp.height / 2));
    return rec.endRecording();
  });
}

TextPainter _label(String text, bool halo) {
  final key = '${halo ? 'h' : 'f'}|$text';
  final cached = _labels[key];
  if (cached != null) return cached;
  if (_labels.length > 600) _labels.clear();
  final style = halo
      ? TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = Colors.white)
      : const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF263238));
  final tp = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: 120);
  return _labels[key] = tp;
}

/// Рисует остановки и города одним проходом по холсту: тысячи значков без тормозов,
/// они двигаются вместе с картой в каждом кадре.
class StopsPainter extends CustomPainter {
  StopsPainter({
    required this.center,
    required this.zoom,
    required this.kinds,
    required this.ink,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final LatLng center;
  final double zoom;
  final Set<StopKind> kinds;
  final bool ink;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = lonToPx(center.longitude, zoom), cy = latToPx(center.latitude, zoom);
    final hw = size.width / 2, hh = size.height / 2;
    const pad = 40.0;
    final b = LatLngBounds(
      LatLng(pxToLat(cy + hh + pad, zoom), pxToLon(cx - hw - pad, zoom)),
      LatLng(pxToLat(cy - hh - pad, zoom), pxToLon(cx + hw + pad, zoom)),
    );
    final objs = selectObjects(b, zoom, kinds);

    for (final d in objs.dots) {
      final x = lonToPx(d.pos.longitude, zoom) - cx + hw;
      final y = latToPx(d.pos.latitude, zoom) - cy + hh;
      final s = switch (d.kind) {
        'city' => 16.0,
        'town' => 12.0,
        'village' => 9.0,
        _ => 7.0,
      };
      final color = switch (d.kind) {
        'city' => const Color(0xFFD32F2F),
        'town' => const Color(0xFFF57C00),
        'village' => const Color(0xFF388E3C),
        _ => const Color(0xFF757575),
      };
      final r = RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, y), width: s, height: s), Radius.circular(s * 0.3));
      canvas.drawRRect(r, Paint()..color = color);
      canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = ink ? Pirate.gold : Colors.white);
    }

    final sz = zoom >= 17 ? 26.0 : (zoom >= 16 ? 22.0 : (zoom >= 15 ? 19.0 : 17.0));
    final labels = zoom >= 16.5 && objs.stops.length <= 150;
    for (final s in objs.stops) {
      final x = lonToPx(s.pos.longitude, zoom) - cx + hw;
      final y = latToPx(s.pos.latitude, zoom) - cy + hh;
      canvas.save();
      canvas.translate(x, y);
      canvas.drawPicture(_sprite(s.kind, sz, ink));
      canvas.restore();
      if (labels) {
        final name = s.name;
        final back = _label(name, true);
        final front = _label(name, false);
        final o = Offset(x - back.width / 2, y + sz / 2 + 2);
        back.paint(canvas, o);
        front.paint(canvas, o);
      }
    }
  }

  @override
  bool shouldRepaint(covariant StopsPainter old) => true;
}

class StopsLayer extends StatelessWidget {
  const StopsLayer({super.key, required this.kinds, required this.repaint, required this.ink});
  final Set<StopKind> kinds;
  final Listenable repaint;
  final bool ink;

  @override
  Widget build(BuildContext context) {
    final cam = MapCamera.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: StopsPainter(center: cam.center, zoom: cam.zoom, kinds: kinds, ink: ink, repaint: repaint),
      ),
    );
  }
}
