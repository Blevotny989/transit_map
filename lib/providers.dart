import 'dart:convert';
import 'package:latlong2/latlong.dart';
import 'config.dart';
import 'models.dart';
import 'services.dart';
import 'transit_planner.dart';

/// Ключи API не заданы.
class NoKeyException implements Exception {
  const NoKeyException();
}

List<String> keysOf(String raw) =>
    raw.split(RegExp(r'[\s,;]+')).where((k) => k.isNotEmpty).toList();

/// Пробует ключи по очереди: если один исчерпал лимит или не подошёл, берёт следующий.
Future<T> withKeys<T>(String raw, Future<T> Function(String key) call) async {
  final keys = keysOf(raw);
  if (keys.isEmpty) throw const NoKeyException();
  Object? last;
  for (final k in keys) {
    try {
      return await call(k);
    } catch (e) {
      last = e;
    }
  }
  throw last!;
}

// ------------------------------------------------------------ регион
const cisCodes = {'ru', 'by', 'kz', 'uz', 'kg', 'tj', 'tm', 'am', 'az', 'md', 'ua', 'ge'};
final Map<String, String> _cc = {};

Future<String> countryCode(LatLng p) async {
  final k = '${(p.latitude * 2).round()},${(p.longitude * 2).round()}';
  final c = _cc[k];
  if (c != null) return c;
  try {
    final d = await getJson(Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': '${p.latitude}',
      'lon': '${p.longitude}',
      'zoom': '3',
      'addressdetails': '1',
      'accept-language': 'en',
    }));
    final cc = '${d['address']?['country_code'] ?? ''}'.toLowerCase();
    return _cc[k] = cc;
  } catch (_) {
    return '';
  }
}

// -------------------------------------------------- маршруты на транспорте
/// Порядок: свой OpenTripPlanner, затем облачные сервисы по региону
/// (СНГ: 2ГИС, потом HERE; остальной мир: HERE, потом 2ГИС), затем данные OpenStreetMap.
Future<List<TransitPlan>> planJourneys(LatLng a, LatLng b) async {
  if (Config.otpUrl.isNotEmpty) {
    try {
      final p = await buildTransitPlans(a, b);
      if (p.isNotEmpty) return p;
    } catch (_) {}
  }
  final cis = cisCodes.contains(await countryCode(a));
  for (final id in cis ? ['2gis', 'here'] : ['here', '2gis']) {
    try {
      final plans = id == 'here' ? await hereJourneys(a, b) : await gisJourneys(a, b);
      if (plans.isNotEmpty) return plans;
    } catch (_) {}
  }
  return planTransit(a, b);
}

double _num(dynamic v) => v is num ? v.toDouble() : 0.0;

String _hereMode(String m) {
  final l = m.toLowerCase();
  if (l.contains('train') || l == 'rail') return 'RAIL';
  return switch (m) {
    'subway' || 'monorail' => 'SUBWAY',
    'lightRail' => 'TRAM',
    'ferry' => 'FERRY',
    _ => 'BUS',
  };
}

LatLng? _hereLoc(dynamic side) {
  final loc = side?['place']?['location'];
  if (loc is Map && loc['lat'] is num && loc['lng'] is num) {
    return LatLng((loc['lat'] as num).toDouble(), (loc['lng'] as num).toDouble());
  }
  return null;
}

DateTime? _hereTime(dynamic side) => DateTime.tryParse('${side?['time'] ?? ''}');

Future<List<TransitPlan>> hereJourneys(LatLng a, LatLng b) => withKeys(Config.hereKeys, (key) async {
      final d = await getJson(Uri.https('transit.router.hereapi.com', '/v8/routes', {
        'origin': '${a.latitude},${a.longitude}',
        'destination': '${b.latitude},${b.longitude}',
        'return': 'intermediate,travelSummary',
        'alternatives': '3',
        'lang': Config.lang,
        'apiKey': key,
      }));
      final out = <TransitPlan>[];
      for (final r in ((d['routes'] as List?) ?? [])) {
        final secs = (r['sections'] as List?) ?? [];
        if (secs.isEmpty) continue;
        final legs = <TransitLeg>[];
        DateTime? prevArr;
        var hasRide = false;
        for (final s in secs) {
          final dep = s['departure'], arr = s['arrival'];
          final pd = _hereLoc(dep), pa = _hereLoc(arr);
          final td = _hereTime(dep), ta = _hereTime(arr);
          var dur = _num(s['travelSummary']?['duration']);
          if (dur == 0 && td != null && ta != null) dur = ta.difference(td).inSeconds.toDouble();
          final from = '${dep?['place']?['name'] ?? ''}';
          final to = '${arr?['place']?['name'] ?? ''}';
          final pts = <LatLng>[if (pd != null) pd];
          for (final st in ((s['intermediateStops'] as List?) ?? [])) {
            final l = _hereLoc(st['departure']);
            if (l != null) pts.add(l);
          }
          if (pa != null) pts.add(pa);
          if ('${s['type']}' == 'transit') {
            hasRide = true;
            final tr = s['transport'] as Map? ?? {};
            var wait = 0.0;
            if (prevArr != null && td != null) {
              wait = td.difference(prevArr).inSeconds.toDouble();
              if (wait < 0) wait = 0;
            }
            legs.add(TransitLeg(_hereMode('${tr['mode']}'), '${tr['name'] ?? tr['headsign'] ?? ''}', from, to,
                dur, pts,
                stops: ((s['intermediateStops'] as List?) ?? []).length + 1, waitSeconds: wait));
          } else {
            legs.add(TransitLeg('WALK', '', from, to, dur, pts));
          }
          prevArr = ta ?? prevArr;
        }
        if (!hasRide) continue;
        final t0 = _hereTime(secs.first['departure']);
        final t1 = _hereTime(secs.last['arrival']);
        final total = (t0 != null && t1 != null)
            ? t1.difference(t0).inSeconds.toDouble()
            : legs.fold<double>(0, (x, l) => x + l.seconds + l.waitSeconds);
        out.add(TransitPlan(total, legs, source: 'HERE'));
      }
      return out;
    });

List<LatLng> _wktPts(String s) {
  final out = <LatLng>[];
  final m = RegExp(r'\(([^()]*)\)').firstMatch(s);
  if (m == null) return out;
  for (final part in m[1]!.split(',')) {
    final xy = part.trim().split(RegExp(r'\s+'));
    if (xy.length >= 2) {
      final lon = double.tryParse(xy[0]), lat = double.tryParse(xy[1]);
      if (lon != null && lat != null) out.add(LatLng(lat, lon));
    }
  }
  return out;
}

List<LatLng> _wktLine(dynamic geom) {
  final out = <LatLng>[];
  if (geom is! List) return out;
  for (final g in geom) {
    final sel = g is Map ? g['selection'] : null;
    if (sel is String) out.addAll(_wktPts(sel));
  }
  return out;
}

List<LatLng> _wktPlatforms(dynamic pl) {
  final out = <LatLng>[];
  if (pl is! List) return out;
  for (final p in pl) {
    final g = p is Map ? p['geometry'] : null;
    if (g is String) out.addAll(_wktPts(g));
  }
  return out;
}

String _gisMode(String m) => switch (m) {
      'metro' || 'premetro' || 'light_metro' || 'monorail' => 'SUBWAY',
      'tram' || 'light_rail' => 'TRAM',
      'trolleybus' => 'TROLLEYBUS',
      'suburban_train' || 'mcd' || 'mcc' || 'aeroexpress' => 'RAIL',
      'river_transport' => 'FERRY',
      _ => 'BUS',
    };

Future<List<TransitPlan>> gisJourneys(LatLng a, LatLng b) => withKeys(Config.gisKeys, (key) async {
      final r = await httpClient
          .post(Uri.parse('https://routing.api.2gis.com/public_transport/2.0?key=$key'),
              headers: {'Content-Type': 'application/json', 'User-Agent': Config.userAgent},
              body: jsonEncode({
                'source': {'point': {'lat': a.latitude, 'lon': a.longitude}},
                'target': {'point': {'lat': b.latitude, 'lon': b.longitude}},
                'transport': [
                  'pedestrian', 'bus', 'trolleybus', 'tram', 'shuttle_bus', 'metro',
                  'suburban_train', 'funicular_railway', 'monorail', 'river_transport',
                  'cable_car', 'light_rail', 'premetro', 'light_metro', 'aeroexpress', 'mcd', 'mcc'
                ],
                'locale': Config.lang == 'ru' ? 'ru' : 'en',
              }))
          .timeout(const Duration(seconds: 25));
      if (r.statusCode != 200) throw Exception('2GIS HTTP ${r.statusCode}');
      final data = jsonDecode(utf8.decode(r.bodyBytes));
      if (data is! List) return <TransitPlan>[];
      final out = <TransitPlan>[];
      for (final route in data) {
        if (route is! Map || route['pedestrian'] == true) continue;
        final ms = (route['movements'] as List?) ?? [];
        final legs = <TransitLeg>[];
        var hasRide = false;
        for (var i = 0; i < ms.length; i++) {
          final m = Map<String, dynamic>.from(ms[i] as Map);
          final type = '${m['type']}';
          final wp = Map<String, dynamic>.from((m['waypoint'] as Map?) ?? {});
          if (type == 'walkway' && '${wp['subtype']}' == 'finish') continue;
          final dur = _num(m['moving_duration']);
          final alts = (m['alternatives'] as List?) ?? [];
          final alt = alts.isNotEmpty ? Map<String, dynamic>.from(alts.first as Map) : <String, dynamic>{};
          final line = _wktLine(alt['geometry']);
          if (type == 'passage') {
            hasRide = true;
            final routes = (m['routes'] as List?) ?? [];
            final metro = m['metro'] as Map?;
            String mode, name;
            if (metro != null) {
              mode = 'SUBWAY';
              name = '${metro['line_name'] ?? ''}';
            } else if (routes.isNotEmpty) {
              mode = _gisMode('${routes[0]['subtype']}');
              name = ((routes[0]['names'] as List?) ?? []).join(', ');
            } else {
              mode = _gisMode('${wp['subtype']}');
              name = '';
            }
            final pnames = ((m['platforms'] as Map?)?['names'] as List?) ?? [];
            final pts = _wktPlatforms(alt['platforms']);
            legs.add(TransitLeg(mode, name, '${wp['name'] ?? ''}',
                pnames.isNotEmpty ? '${pnames.last}' : '', dur, pts.length >= 2 ? pts : line,
                stops: pnames.length, waitSeconds: _num(m['waiting_duration'])));
          } else {
            var to = '';
            if (type == 'crossing') {
              to = '${wp['name'] ?? ''}';
            } else {
              for (var j = i + 1; j < ms.length; j++) {
                final nm = ms[j] as Map;
                if ('${nm['type']}' == 'passage') {
                  to = '${(nm['waypoint'] as Map?)?['name'] ?? ''}';
                  break;
                }
              }
            }
            legs.add(TransitLeg('WALK', '', '', to, dur, line));
          }
        }
        if (!hasRide) continue;
        out.add(TransitPlan(_num(route['total_duration']), legs, source: '2ГИС'));
      }
      out.sort((x, y) => x.seconds.compareTo(y.seconds));
      return out.take(3).toList();
    });

// --------------------------------------------------- расписание отправлений
class DepartureResult {
  final List<Departure> items;
  final String source;
  DepartureResult(this.items, this.source);
}

/// СНГ: Яндекс.Расписания, потом HERE, потом Transitland. Остальной мир: HERE, Transitland, Яндекс.
Future<DepartureResult> loadDeparturesSmart(LatLng pos) async {
  final cis = cisCodes.contains(await countryCode(pos));
  final order = cis ? ['yandex', 'here', 'transitland'] : ['here', 'transitland', 'yandex'];
  var anyKey = false;
  for (final id in order) {
    try {
      final List<Departure> d = switch (id) {
        'here' => await hereDepartures(pos),
        'yandex' => await yandexDepartures(pos),
        _ => await transitlandDepartures(pos),
      };
      anyKey = true;
      if (d.isNotEmpty) {
        return DepartureResult(
            d, switch (id) { 'here' => 'HERE', 'yandex' => 'Яндекс.Расписания', _ => 'Transitland' });
      }
    } on NoKeyException {
      continue;
    } catch (_) {
      anyKey = true;
    }
  }
  if (!anyKey) throw const NoKeyException();
  return DepartureResult([], '');
}

Future<List<Departure>> hereDepartures(LatLng p) => withKeys(Config.hereKeys, (key) async {
      final d = await getJson(Uri.https('transit.router.hereapi.com', '/v8/departures', {
        'in': '${p.latitude},${p.longitude}',
        'lang': Config.lang,
        'apiKey': key,
      }));
      final pairs = <MapEntry<String, Departure>>[];
      for (final b in ((d['boards'] as List?) ?? [])) {
        for (final x in ((b['departures'] as List?) ?? [])) {
          final t = '${x['time'] ?? ''}';
          final tr = (x['transport'] as Map?) ?? {};
          pairs.add(MapEntry(t,
              Departure(t.length >= 16 ? t.substring(11, 16) : t, '${tr['name'] ?? ''}', '${tr['headsign'] ?? ''}')));
        }
      }
      pairs.sort((x, y) => x.key.compareTo(y.key));
      return pairs.take(14).map((e) => e.value).toList();
    });

Future<List<Departure>> yandexDepartures(LatLng p) => withKeys(Config.yandexKeys, (key) async {
      final ns = await getJson(Uri.https('api.rasp.yandex.net', '/v3.0/nearest_stations/', {
        'apikey': key,
        'format': 'json',
        'lat': '${p.latitude}',
        'lng': '${p.longitude}',
        'distance': '1',
        'lang': 'ru_RU',
      }));
      final stations = ((ns['stations'] as List?) ?? []).take(3).toList();
      final now = DateTime.now();
      final date = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final pairs = <MapEntry<String, Departure>>[];
      for (final st in stations) {
        try {
          final sc = await getJson(Uri.https('api.rasp.yandex.net', '/v3.0/schedule/', {
            'apikey': key,
            'format': 'json',
            'station': '${st['code']}',
            'date': date,
            'lang': 'ru_RU',
          }));
          for (final x in ((sc['schedule'] as List?) ?? [])) {
            final dep = x['departure'];
            if (dep is! String) continue;
            final dt = DateTime.tryParse(dep);
            if (dt == null || dt.isBefore(now)) continue;
            final th = (x['thread'] as Map?) ?? {};
            pairs.add(MapEntry(dep,
                Departure(dep.length >= 16 ? dep.substring(11, 16) : dep, '${th['number'] ?? ''}', '${th['title'] ?? ''}')));
          }
        } catch (_) {}
      }
      pairs.sort((x, y) => x.key.compareTo(y.key));
      return pairs.take(14).map((e) => e.value).toList();
    });

Future<List<Departure>> transitlandDepartures(LatLng pos) => withKeys(Config.transitlandKey, (key) async {
      final stops = await getJson(Uri.https('transit.land', '/api/v2/rest/stops', {
        'lat': '${pos.latitude}',
        'lon': '${pos.longitude}',
        'radius': '120',
        'limit': '1',
        'apikey': key,
      }));
      final list = (stops['stops'] as List?) ?? [];
      if (list.isEmpty) return <Departure>[];
      final id = Uri.encodeComponent('${list[0]['onestop_id']}');
      final dep = await getJson(Uri.parse(
          'https://transit.land/api/v2/rest/stops/$id/departures?limit=12&apikey=$key'));
      final out = <Departure>[];
      for (final s in (dep['stops'] as List? ?? [])) {
        for (final d in (s['departures'] as List? ?? [])) {
          final time = '${d['departure']?['estimated'] ?? d['departure']?['scheduled'] ?? ''}';
          out.add(Departure(time.length >= 5 ? time.substring(0, 5) : time,
              '${d['trip']?['route']?['route_short_name'] ?? ''}', '${d['trip']?['trip_headsign'] ?? ''}'));
        }
      }
      return out;
    });
