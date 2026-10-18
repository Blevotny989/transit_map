import 'dart:math';
import 'package:latlong2/latlong.dart';
import 'models.dart';
import 'services.dart';

/// Подбор маршрута на общественном транспорте по данным OpenStreetMap:
/// прямые линии и варианты с одной пересадкой. Время приблизительное.

double _m(LatLng a, LatLng b) {
  const k = 111320.0;
  final dy = (a.latitude - b.latitude) * k;
  final dx = (a.longitude - b.longitude) * k * cos(a.latitude * pi / 180);
  return sqrt(dx * dx + dy * dy);
}

const _walkMpm = 80.0; // метров в минуту
double _walkMin(double meters) => meters * 1.3 / _walkMpm;

double _speedKmh(String mode) => switch (mode) {
      'subway' => 32.0,
      'train' => 45.0,
      'light_rail' => 30.0,
      'monorail' => 30.0,
      'tram' => 17.0,
      'ferry' => 20.0,
      _ => 18.0,
    };

double _waitMin(RouteInfo r) {
  final iv = r.interval.trim();
  double? mins;
  if (RegExp(r'^\d+(\.\d+)?$').hasMatch(iv)) {
    mins = double.parse(iv);
  } else {
    final m = RegExp(r'^(\d+):(\d+)').firstMatch(iv);
    if (m != null) mins = (int.parse(m[1]!) * 60 + int.parse(m[2]!)).toDouble();
  }
  if (mins != null && mins > 0 && mins < 180) return mins / 2;
  return switch (r.mode) {
    'subway' => 3.0,
    'train' => 15.0,
    'ferry' => 20.0,
    'tram' => 7.0,
    _ => 8.0,
  };
}

int _nearest(List<StopPt> s, LatLng p, double maxM) {
  var best = -1;
  var bd = maxM;
  for (var i = 0; i < s.length; i++) {
    final d = _m(s[i].pos, p);
    if (d < bd) {
      bd = d;
      best = i;
    }
  }
  return best;
}

List<double> _cum(List<StopPt> s) {
  final c = List<double>.filled(s.length, 0);
  for (var i = 1; i < s.length; i++) {
    c[i] = c[i - 1] + _m(s[i - 1].pos, s[i].pos);
  }
  return c;
}

class _Opt {
  final double minutes;
  final List<TransitLeg> legs;
  final String sig;
  _Opt(this.minutes, this.legs, this.sig);
}

TransitLeg _walk(String from, String to, LatLng a, LatLng b) =>
    TransitLeg('WALK', '', from, to, _walkMin(_m(a, b)) * 60, [a, b]);

TransitLeg _ride(RouteInfo r, List<StopPt> s, List<double> cum, int i, int j) {
  final meters = (cum[j] - cum[i]) * 1.15;
  final minutes = meters / (_speedKmh(r.mode) * 1000 / 60);
  return TransitLeg(
    legModeFor(r.mode),
    r.ref.isNotEmpty ? r.ref : r.name,
    s[i].name,
    s[j].name,
    minutes * 60,
    [for (var k = i; k <= j; k++) s[k].pos],
    stops: j - i,
    waitSeconds: _waitMin(r) * 60,
  );
}

double _total(List<TransitLeg> legs) =>
    legs.fold<double>(0, (a, l) => a + l.seconds + l.waitSeconds) / 60;

/// Сначала ищет по ближайшим остановкам, а если ничего не нашлось, расширяет поиск.
Future<List<TransitPlan>> planTransit(LatLng a, LatLng b) async {
  try {
    return await _plan(a, b, 400);
  } catch (_) {
    return _plan(a, b, 1200);
  }
}

Future<List<TransitPlan>> _plan(LatLng a, LatLng b, int radius) async {
  final c = await Future.wait([loadCandidateRoutes(a, radius), loadCandidateRoutes(b, radius)]);
  final ca = c[0], cb = c[1];
  if (ca.isEmpty) {
    throw Exception('Рядом с точкой «откуда» нет остановок с маршрутами в OpenStreetMap');
  }
  if (cb.isEmpty) {
    throw Exception('Рядом с точкой «куда» нет остановок с маршрутами в OpenStreetMap');
  }
  final infos = <int, RouteInfo>{for (final r in [...ca, ...cb]) r.id: r};
  final idsA = ca.map((e) => e.id).toSet();
  final idsB = cb.map((e) => e.id).toSet();
  final both = idsA.intersection(idsB);
  final ids = <int>[
    ...both,
    ...idsA.difference(both).take(25),
    ...idsB.difference(both).take(25),
  ];
  final rels = await loadRelationStops(ids);

  final ia = <int, int>{};
  final ib = <int, int>{};
  final cums = <int, List<double>>{};
  for (final id in ids) {
    final s = rels[id];
    if (s == null || s.length < 2) continue;
    cums[id] = _cum(s);
    ia[id] = idsA.contains(id) ? _nearest(s, a, 700) : -1;
    ib[id] = idsB.contains(id) ? _nearest(s, b, 700) : -1;
  }

  final opts = <_Opt>[];

  // прямые маршруты
  for (final id in ids) {
    final s = rels[id];
    if (s == null || !cums.containsKey(id)) continue;
    final i = ia[id]!, j = ib[id]!;
    if (i >= 0 && j >= 0 && i < j) {
      final r = infos[id]!;
      final legs = [
        _walk('Старт', s[i].name, a, s[i].pos),
        _ride(r, s, cums[id]!, i, j),
        _walk(s[j].name, 'Финиш', s[j].pos, b),
      ];
      opts.add(_Opt(_total(legs), legs, '${legModeFor(r.mode)}${r.ref}'));
    }
  }

  // с одной пересадкой
  for (final id1 in ids) {
    final i1 = ia[id1] ?? -1;
    if (i1 < 0) continue;
    final s1 = rels[id1]!;
    for (final id2 in ids) {
      if (id2 == id1) continue;
      final j2 = ib[id2] ?? -1;
      if (j2 <= 0) continue;
      final s2 = rels[id2]!;
      final r1 = infos[id1]!, r2 = infos[id2]!;
      final v1 = _speedKmh(r1.mode) * 1000 / 60;
      final v2 = _speedKmh(r2.mode) * 1000 / 60;
      var best = double.infinity;
      var bk = -1, bm = -1;
      for (var k = i1 + 1; k < s1.length; k++) {
        for (var m = 0; m < j2; m++) {
          if ((s1[k].pos.latitude - s2[m].pos.latitude).abs() > 0.0025) continue;
          final dd = _m(s1[k].pos, s2[m].pos);
          if (dd > 250) continue;
          final cost = (cums[id1]![k] - cums[id1]![i1]) * 1.15 / v1 +
              _walkMin(dd) +
              (cums[id2]![j2] - cums[id2]![m]) * 1.15 / v2;
          if (cost < best) {
            best = cost;
            bk = k;
            bm = m;
          }
        }
      }
      if (bk < 0) continue;
      final legs = [
        _walk('Старт', s1[i1].name, a, s1[i1].pos),
        _ride(r1, s1, cums[id1]!, i1, bk),
        if (_m(s1[bk].pos, s2[bm].pos) > 15) _walk(s1[bk].name, s2[bm].name, s1[bk].pos, s2[bm].pos),
        _ride(r2, s2, cums[id2]!, bm, j2),
        _walk(s2[j2].name, 'Финиш', s2[j2].pos, b),
      ];
      opts.add(_Opt(_total(legs) + 3, legs,
          '${legModeFor(r1.mode)}${r1.ref}>${legModeFor(r2.mode)}${r2.ref}'));
    }
  }

  if (opts.isEmpty) {
    throw Exception('Подходящих маршрутов в данных OpenStreetMap не найдено '
        '(возможно, нужно больше одной пересадки)');
  }
  opts.sort((x, y) => x.minutes.compareTo(y.minutes));
  final seen = <String>{};
  final res = <TransitPlan>[];
  for (final o in opts) {
    if (!seen.add(o.sig)) continue;
    res.add(TransitPlan(o.minutes * 60, o.legs, estimated: true, source: 'OpenStreetMap'));
    if (res.length >= 3) break;
  }
  return res;
}
