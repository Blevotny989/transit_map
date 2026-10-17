import 'dart:convert';
import 'dart:math' show sqrt;
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'config.dart';
import 'models.dart';

const _hdr = {'User-Agent': Config.userAgent, 'Accept-Language': 'ru'};
final http.Client _client = http.Client();

Future<dynamic> _getJson(Uri uri) async {
  final r = await _client.get(uri, headers: _hdr).timeout(const Duration(seconds: 25));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

const _mirrors = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
];

/// Запрос к Overpass с переключением на запасные серверы.
Future<dynamic> _overpass(String query) async {
  Object? last;
  for (final url in _mirrors) {
    try {
      final r = await _client
          .post(Uri.parse(url), headers: _hdr, body: {'data': query})
          .timeout(const Duration(seconds: 30));
      if (r.statusCode == 200) return jsonDecode(utf8.decode(r.bodyBytes));
      last = 'HTTP ${r.statusCode}';
    } catch (e) {
      last = e;
    }
  }
  throw Exception('Сервер данных недоступен: $last');
}

String _bbox(LatLngBounds b) => '${b.south},${b.west},${b.north},${b.east}';

// ---------------------------------------------------------------- остановки
Future<List<Stop>> loadStops(LatLngBounds b) async {
  final bb = _bbox(b);
  final q = '[out:json][timeout:25];('
      'nwr["highway"="bus_stop"]($bb);'
      'nwr["railway"~"^(station|halt|tram_stop)\$"]($bb);'
      'nwr["amenity"~"^(ferry_terminal|bus_station)\$"]($bb);'
      ');out center 400;';
  final data = await _overpass(q);
  final res = <Stop>[];
  for (final e in (data['elements'] as List)) {
    final c = e['center'] as Map?;
    final lat = (e['lat'] ?? c?['lat']) as num?;
    final lon = (e['lon'] ?? c?['lon']) as num?;
    if (lat == null || lon == null) continue;
    final tags = <String, String>{
      for (final en in (e['tags'] as Map? ?? {}).entries) '${en.key}': '${en.value}'
    };
    final kind = Stop.kindFromTags(tags);
    res.add(Stop(
      e['id'] as int,
      LatLng(lat.toDouble(), lon.toDouble()),
      tags['name:ru'] ?? tags['name'] ?? kind.label,
      kind,
      tags,
    ));
  }
  return res;
}

// ------------------------------------------------- города, деревни, посёлки
Future<List<PlaceDot>> loadPlaceDots(LatLngBounds b, double zoom) async {
  final kinds = zoom < 10
      ? 'city|town'
      : zoom < 12
          ? 'city|town|village'
          : 'city|town|village|hamlet';
  final q = '[out:json][timeout:25];'
      'node["place"~"^($kinds)\$"]["name"](${_bbox(b)});out 400;';
  final data = await _overpass(q);
  const order = {'city': 0, 'town': 1, 'village': 2, 'hamlet': 3};
  final res = <PlaceDot>[];
  for (final e in (data['elements'] as List)) {
    final t = Map<String, dynamic>.from(e['tags'] ?? {});
    final lat = e['lat'] as num?;
    final lon = e['lon'] as num?;
    if (lat == null || lon == null) continue;
    res.add(PlaceDot('${t['name:ru'] ?? t['name']}', LatLng(lat.toDouble(), lon.toDouble()),
        '${t['place']}', int.tryParse('${t['population'] ?? ''}')));
  }
  res.sort((a, b) => (order[a.kind] ?? 9).compareTo(order[b.kind] ?? 9));
  return res;
}

// ------------------------------------------------------ маршруты на остановке
List<RouteInfo> _parseRoutes(dynamic data) {
  final seen = <int>{};
  final list = <RouteInfo>[];
  for (final e in (data['elements'] as List)) {
    final id = e['id'] as int;
    if (!seen.add(id)) continue;
    final t = Map<String, dynamic>.from(e['tags'] ?? {});
    list.add(RouteInfo(
      id,
      '${t['route']}',
      '${t['ref'] ?? ''}',
      '${t['name'] ?? ''}',
      '${t['from'] ?? ''}',
      '${t['to'] ?? ''}',
      '${t['operator'] ?? ''}',
      '${t['interval'] ?? ''}',
      '${t['opening_hours'] ?? ''}',
    ));
  }
  list.sort((a, b) => a.ref.compareTo(b.ref));
  return list;
}

/// Маршруты (линии), проходящие через остановки в радиусе [radius] метров от точки.
Future<List<RouteInfo>> loadCandidateRoutes(LatLng pos, int radius) async {
  final a = '${pos.latitude},${pos.longitude}';
  final q = '[out:json][timeout:30];('
      'node(around:$radius,$a)["public_transport"];'
      'node(around:$radius,$a)["highway"="bus_stop"];'
      'node(around:$radius,$a)["railway"~"^(stop|tram_stop|station|halt)\$"];'
      ');rel(bn)["route"~"^(bus|tram|trolleybus|train|subway|light_rail|ferry|monorail)\$"];'
      'out tags;';
  return _parseRoutes(await _overpass(q));
}

Future<List<RouteInfo>> loadRoutesAtStop(LatLng pos) => loadCandidateRoutes(pos, 70);

/// Остановки вдоль маршрутов по порядку (нужны для подбора пересадок).
Future<Map<int, List<StopPt>>> loadRelationStops(List<int> ids) async {
  final sb = StringBuffer('[out:json][timeout:60];(');
  for (final i in ids) {
    sb.write('rel($i);');
  }
  sb.write(');out body;node(r);out body;');
  final data = await _overpass(sb.toString());
  final nodes = <int, StopPt>{};
  final rels = <Map>[];
  for (final e in (data['elements'] as List)) {
    if (e['type'] == 'node') {
      final t = Map<String, dynamic>.from(e['tags'] ?? {});
      nodes[e['id'] as int] = StopPt(
        e['id'] as int,
        LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()),
        '${t['name:ru'] ?? t['name'] ?? ''}',
      );
    } else if (e['type'] == 'relation') {
      rels.add(e as Map);
    }
  }
  final out = <int, List<StopPt>>{};
  for (final r in rels) {
    final members = (r['members'] as List).where((m) => m['type'] == 'node').toList();
    var sel = members.where((m) => '${m['role']}'.startsWith('stop')).toList();
    if (sel.isEmpty) sel = members.where((m) => '${m['role']}'.startsWith('platform')).toList();
    if (sel.isEmpty) sel = members;
    final named = [
      for (final m in members)
        if (nodes[m['ref']] != null && nodes[m['ref']]!.name.isNotEmpty) nodes[m['ref']]!
    ];
    final list = <StopPt>[];
    for (final m in sel) {
      final n = nodes[m['ref']];
      if (n == null) continue;
      var name = n.name;
      if (name.isEmpty) {
        double best = 90;
        for (final c in named) {
          final dy = (c.pos.latitude - n.pos.latitude) * 111320;
          final dx = (c.pos.longitude - n.pos.longitude) * 111320 * 0.6;
          final d = (dx * dx + dy * dy);
          if (d < best * best) {
            best = sqrt(d);
            name = c.name;
          }
        }
      }
      list.add(StopPt(n.id, n.pos, name.isEmpty ? 'остановка' : name));
    }
    out[r['id'] as int] = list;
  }
  return out;
}

/// Линия маршрута (пути) для показа на карте.
Future<List<List<LatLng>>> loadRouteGeometry(int relId) async {
  final data = await _overpass('[out:json][timeout:30];rel($relId);out geom;');
  final els = data['elements'] as List;
  if (els.isEmpty) return [];
  final res = <List<LatLng>>[];
  for (final m in (els[0]['members'] as List? ?? [])) {
    if (m['type'] == 'way' && m['geometry'] != null) {
      res.add([
        for (final g in (m['geometry'] as List))
          LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble())
      ]);
    }
  }
  return res;
}

// ------------------------------------------------------------------- поиск
final Map<String, List<Place>> _searchCache = {};

Future<List<Place>> searchPlaces(String query, LatLng bias) async {
  final ck = query.trim().toLowerCase();
  final cached = _searchCache[ck];
  if (cached != null) return cached;
  try {
    final data = await _getJson(Uri.https('photon.komoot.io', '/api/', {
      'q': query,
      'limit': '6',
      'lat': '${bias.latitude}',
      'lon': '${bias.longitude}',
    }));
    final out = <Place>[];
    for (final f in (data['features'] as List)) {
      final p = Map<String, dynamic>.from(f['properties'] ?? {});
      final c = f['geometry']['coordinates'] as List;
      final name = '${p['name'] ?? p['street'] ?? ''}';
      if (name.isEmpty) continue;
      final sub = [p['street'], p['city'], p['state'], p['country']]
          .where((x) => x != null && '$x'.isNotEmpty && '$x' != name)
          .join(', ');
      out.add(Place(name, LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()), sub));
    }
    if (out.isNotEmpty) return _searchCache[ck] = out;
  } catch (_) {}
  // запасной вариант — Nominatim
  final data = await _getJson(Uri.https('nominatim.openstreetmap.org', '/search',
      {'q': query, 'format': 'json', 'limit': '8', 'accept-language': 'ru'})) as List;
  return [
    for (final e in data)
      Place(
        '${e['display_name']}'.split(',').first,
        LatLng(double.parse('${e['lat']}'), double.parse('${e['lon']}')),
        '${e['display_name']}'.split(',').skip(1).join(',').trim(),
      )
  ];
}

// ------------------------------------------------------- сводка об объекте
const _typeRu = {
  'city': 'Город',
  'town': 'Город / посёлок',
  'village': 'Деревня / село',
  'hamlet': 'Хутор / малая деревня',
  'suburb': 'Район города',
  'neighbourhood': 'Микрорайон',
  'quarter': 'Квартал',
  'administrative': 'Административная единица',
  'state': 'Область / регион',
  'county': 'Район',
  'country': 'Страна',
  'bus_stop': 'Автобусная остановка',
  'station': 'Станция',
  'halt': 'Ж/д платформа',
  'tram_stop': 'Трамвайная остановка',
  'bus_station': 'Автовокзал',
  'ferry_terminal': 'Паромный терминал',
  'aerodrome': 'Аэропорт',
  'residential': 'Жилая улица',
  'house': 'Здание',
  'yes': 'Здание',
  'restaurant': 'Ресторан',
  'cafe': 'Кафе',
  'hospital': 'Больница',
  'school': 'Школа',
  'university': 'Университет',
  'pharmacy': 'Аптека',
  'supermarket': 'Супермаркет',
  'park': 'Парк',
  'museum': 'Музей',
  'hotel': 'Гостиница',
  'place_of_worship': 'Культовое здание',
  'attraction': 'Достопримечательность',
  'peak': 'Вершина',
  'water': 'Водоём',
  'river': 'Река',
  'primary': 'Магистраль',
  'secondary': 'Дорога',
  'tertiary': 'Дорога',
  'unclassified': 'Дорога',
  'service': 'Служебный проезд',
  'footway': 'Пешеходная дорожка',
};

Future<ObjectInfo> loadObjectInfo(LatLng p, double mapZoom) async {
  final z = (mapZoom + 1).round().clamp(5, 18);
  final d = await _getJson(Uri.https('nominatim.openstreetmap.org', '/reverse', {
    'format': 'jsonv2',
    'lat': '${p.latitude}',
    'lon': '${p.longitude}',
    'zoom': '$z',
    'addressdetails': '1',
    'extratags': '1',
    'namedetails': '1',
    'accept-language': 'ru',
  }));
  if (d is! Map || d['error'] != null) throw Exception('Объект не найден');
  final extra = Map<String, dynamic>.from(d['extratags'] ?? {});
  final addr = Map<String, dynamic>.from(d['address'] ?? {});
  final display = '${d['display_name'] ?? ''}';
  var title = '${d['name'] ?? ''}';
  if (title.isEmpty) {
    title = '${addr['road'] ?? ''}'.isNotEmpty ? '${addr['road']}' : display.split(',').first;
  }
  final type = '${d['type'] ?? ''}';
  final cat = '${d['category'] ?? ''}';
  final typeLabel = _typeRu[type] ?? _typeRu[cat] ?? type.replaceAll('_', ' ');

  final facts = <MapEntry<String, String>>[];
  void add(String label, dynamic v) {
    if (v != null && '$v'.isNotEmpty) facts.add(MapEntry(label, '$v'));
  }

  add('Население', extra['population']);
  add('Оператор', extra['operator']);
  add('Сайт', extra['website'] ?? extra['contact:website']);
  add('Телефон', extra['phone'] ?? extra['contact:phone']);
  add('Часы работы', extra['opening_hours']);
  add('Высота, м', extra['ele']);
  add('Координаты',
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}');

  String? wText, wImg, wUrl;
  final w = extra['wikipedia'];
  if (w is String && w.contains(':')) {
    try {
      final i = w.indexOf(':');
      final s = await _getJson(Uri.https('${w.substring(0, i)}.wikipedia.org',
          '/api/rest_v1/page/summary/${w.substring(i + 1)}'));
      wText = s['extract'] as String?;
      wImg = s['thumbnail']?['source'] as String?;
      wUrl = s['content_urls']?['desktop']?['page'] as String?;
    } catch (_) {}
  }
  return ObjectInfo(title, typeLabel, display, facts,
      wikiText: wText, wikiImage: wImg, wikiUrl: wUrl);
}

// ------------------------------------------------------------------ радар
Future<RadarData> loadRadar() async {
  final d = await _getJson(Uri.parse('https://api.rainviewer.com/public/weather-maps.json'));
  final past = (d['radar']['past'] as List?) ?? [];
  final now = (d['radar']['nowcast'] as List?) ?? [];
  final frames = <RadarFrame>[
    for (final f in past) RadarFrame('${f['path']}', (f['time'] as num).toInt(), false),
    for (final f in now) RadarFrame('${f['path']}', (f['time'] as num).toInt(), true),
  ];
  if (frames.isEmpty) throw Exception('Нет кадров радара');
  return RadarData('${d['host']}', frames, past.isEmpty ? 0 : past.length - 1);
}

// ----------------------------------------------------------------- погода
double _n(dynamic v) => v is num ? v.toDouble() : 0.0;

Future<WeatherInfo> loadWeather(LatLng p) async {
  final d = await _getJson(Uri.https('api.open-meteo.com', '/v1/forecast', {
    'latitude': '${p.latitude}',
    'longitude': '${p.longitude}',
    'current': 'temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,'
        'weather_code,cloud_cover,wind_speed_10m,pressure_msl',
    'hourly': 'temperature_2m,precipitation_probability,precipitation,weather_code',
    'daily': 'precipitation_sum,precipitation_probability_max,temperature_2m_max,temperature_2m_min',
    'minutely_15': 'precipitation',
    'forecast_days': '2',
    'timezone': 'auto',
    'wind_speed_unit': 'ms',
  }));
  final cur = Map<String, dynamic>.from(d['current'] ?? {});
  final curTime = '${cur['time'] ?? ''}';
  final h = Map<String, dynamic>.from(d['hourly'] ?? {});
  final times = (h['time'] as List?) ?? [];
  final hourPrefix = curTime.length >= 13 ? curTime.substring(0, 13) : '';
  var start = times.indexWhere((t) => '$t'.compareTo(hourPrefix) >= 0);
  if (start < 0) start = 0;
  final hours = <WeatherHour>[];
  for (var i = start; i < times.length && hours.length < 12; i++) {
    hours.add(WeatherHour(
      '${times[i]}'.substring(11, 13),
      _n(h['temperature_2m']?[i]),
      _n(h['precipitation_probability']?[i]),
      _n(h['precipitation']?[i]),
      _n(h['weather_code']?[i]).round(),
    ));
  }
  final dd = Map<String, dynamic>.from(d['daily'] ?? {});

  String? nowcast;
  final m15 = d['minutely_15'];
  if (m15 is Map) {
    final mt = (m15['time'] as List?) ?? [];
    final mp = (m15['precipitation'] as List?) ?? [];
    final s = mt.indexWhere((t) => '$t'.compareTo(curTime) >= 0);
    if (s >= 0) {
      final next = <double>[for (var i = s; i < s + 4 && i < mp.length; i++) _n(mp[i])];
      final sum = next.fold<double>(0, (a, b) => a + b);
      if (next.isNotEmpty) {
        if (sum <= 0.01) {
          nowcast = 'В ближайший час осадков не ожидается';
        } else if (next.first > 0.01) {
          nowcast = 'Осадки идут сейчас, за ближайший час ≈ ${sum.toStringAsFixed(1)} мм';
        } else {
          final idx = next.indexWhere((x) => x > 0.01);
          nowcast = 'Осадки начнутся примерно через ${idx * 15} мин '
              '(≈ ${sum.toStringAsFixed(1)} мм за час)';
        }
      }
    }
  }

  return WeatherInfo(
    temp: _n(cur['temperature_2m']),
    feels: _n(cur['apparent_temperature']),
    humidity: _n(cur['relative_humidity_2m']),
    wind: _n(cur['wind_speed_10m']),
    pressureMm: _n(cur['pressure_msl']) * 0.75006,
    cloud: _n(cur['cloud_cover']),
    precip: _n(cur['precipitation']),
    code: _n(cur['weather_code']).round(),
    hours: hours,
    daySum: _n(dd['precipitation_sum']?[0]),
    dayProb: _n(dd['precipitation_probability_max']?[0]),
    tMax: _n(dd['temperature_2m_max']?[0]),
    tMin: _n(dd['temperature_2m_min']?[0]),
    nowcast: nowcast,
  );
}

// --------------------------------------------------------------- маршруты
Future<RouteResult> buildRoute(LatLng a, LatLng b, RouteMode mode) async {
  final profile = switch (mode) {
    RouteMode.walk => 'routed-foot',
    RouteMode.bike => 'routed-bike',
    _ => 'routed-car',
  };
  final uri = Uri.parse('https://routing.openstreetmap.de/$profile/route/v1/driving/'
      '${a.longitude},${a.latitude};${b.longitude},${b.latitude}'
      '?overview=full&geometries=geojson');
  final data = await _getJson(uri);
  if (data['routes'] == null || (data['routes'] as List).isEmpty) {
    throw Exception('Маршрут не найден');
  }
  final r = data['routes'][0];
  final pts = [
    for (final c in (r['geometry']['coordinates'] as List))
      LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble())
  ];
  return RouteResult(pts, (r['distance'] as num).toDouble(), (r['duration'] as num).toDouble());
}

Future<List<TransitPlan>> buildTransitPlans(LatLng a, LatLng b) async {
  final uri = Uri.parse('${Config.otpUrl}/otp/routers/default/plan'
      '?fromPlace=${a.latitude},${a.longitude}&toPlace=${b.latitude},${b.longitude}'
      '&mode=TRANSIT,WALK&numItineraries=3');
  final data = await _getJson(uri);
  final its = (data['plan']?['itineraries'] as List?) ?? [];
  if (its.isEmpty) throw Exception('Маршрут на транспорте не найден');
  return [
    for (final it in its)
      TransitPlan((it['duration'] as num).toDouble(), [
        for (final l in (it['legs'] as List))
          TransitLeg(
            '${l['mode']}',
            '${l['routeShortName'] ?? l['route'] ?? ''}',
            '${l['from']?['name'] ?? ''}',
            '${l['to']?['name'] ?? ''}',
            (l['duration'] as num).toDouble(),
            decodePolyline('${l['legGeometry']?['points'] ?? ''}'),
          )
      ])
  ];
}

Future<List<Departure>> loadDepartures(LatLng pos) async {
  final key = Config.transitlandKey;
  if (key.isEmpty) return [];
  final stops = await _getJson(Uri.https('transit.land', '/api/v2/rest/stops', {
    'lat': '${pos.latitude}',
    'lon': '${pos.longitude}',
    'radius': '120',
    'limit': '1',
    'apikey': key,
  }));
  final list = (stops['stops'] as List?) ?? [];
  if (list.isEmpty) return [];
  final id = Uri.encodeComponent('${list[0]['onestop_id']}');
  final dep = await _getJson(Uri.parse(
      'https://transit.land/api/v2/rest/stops/$id/departures?limit=12&apikey=$key'));
  final out = <Departure>[];
  for (final s in (dep['stops'] as List? ?? [])) {
    for (final d in (s['departures'] as List? ?? [])) {
      final time = '${d['departure']?['estimated'] ?? d['departure']?['scheduled'] ?? ''}';
      final route = '${d['trip']?['route']?['route_short_name'] ?? ''}';
      final head = '${d['trip']?['trip_headsign'] ?? ''}';
      out.add(Departure(time.length >= 5 ? time.substring(0, 5) : time, route, head));
    }
  }
  return out;
}

List<LatLng> decodePolyline(String s) {
  final pts = <LatLng>[];
  int i = 0, lat = 0, lng = 0;
  while (i < s.length) {
    for (final isLat in [true, false]) {
      int shift = 0, result = 0, byte;
      do {
        byte = s.codeUnitAt(i++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      final d = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      if (isLat) {
        lat += d;
      } else {
        lng += d;
      }
    }
    pts.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return pts;
}
