import 'dart:convert';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'config.dart';
import 'models.dart';

const _headers = {'User-Agent': Config.userAgent};

Future<dynamic> _getJson(Uri uri) async {
  final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 25));
  if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

Future<dynamic> _overpass(String query) async {
  final r = await http
      .post(Uri.parse('https://overpass-api.de/api/interpreter'),
          headers: _headers, body: {'data': query})
      .timeout(const Duration(seconds: 30));
  if (r.statusCode != 200) throw Exception('Overpass HTTP ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes));
}

/// Остановки, станции и терминалы в видимой области карты (OpenStreetMap).
Future<List<Stop>> loadStops(LatLngBounds b) async {
  final bbox = '${b.south},${b.west},${b.north},${b.east}';
  final q = '[out:json][timeout:25];('
      'node["highway"="bus_stop"]($bbox);'
      'node["railway"~"^(station|halt|tram_stop)\$"]($bbox);'
      'node["amenity"="ferry_terminal"]($bbox);'
      'node["amenity"="bus_station"]($bbox);'
      ');out tags 500;';
  final data = await _overpass(q);
  final res = <Stop>[];
  for (final e in (data['elements'] as List)) {
    final tags = <String, String>{
      for (final en in (e['tags'] as Map? ?? {}).entries) '${en.key}': '${en.value}'
    };
    res.add(Stop(
      e['id'] as int,
      LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()),
      tags['name'] ?? tags['name:ru'] ?? 'Без названия',
      Stop.kindFromTags(tags),
      tags,
    ));
  }
  return res;
}

/// Маршруты (линии), проходящие через остановку: номер, откуда, куда, оператор.
Future<List<RouteInfo>> loadRoutesAtStop(int nodeId) async {
  final q = '[out:json][timeout:25];node($nodeId);'
      'rel(bn)["route"~"bus|tram|trolleybus|train|subway|light_rail|ferry|monorail"];'
      'out tags;';
  final data = await _overpass(q);
  final list = <RouteInfo>[];
  for (final e in (data['elements'] as List)) {
    final t = Map<String, dynamic>.from(e['tags'] ?? {});
    list.add(RouteInfo('${t['route']}', '${t['ref'] ?? ''}', '${t['name'] ?? ''}',
        '${t['from'] ?? ''}', '${t['to'] ?? ''}', '${t['operator'] ?? ''}'));
  }
  list.sort((a, b) => a.ref.compareTo(b.ref));
  return list;
}

/// Поиск места по названию (Nominatim / OpenStreetMap).
Future<List<Place>> searchPlaces(String query) async {
  final uri = Uri.https('nominatim.openstreetmap.org', '/search',
      {'q': query, 'format': 'json', 'limit': '6', 'accept-language': 'ru'});
  final data = await _getJson(uri) as List;
  return [
    for (final e in data)
      Place('${e['display_name']}',
          LatLng(double.parse('${e['lat']}'), double.parse('${e['lon']}')))
  ];
}

/// Пешком / авто / велосипед через открытый сервер routing.openstreetmap.de.
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

/// Маршруты на общественном транспорте по расписанию (нужен ваш OpenTripPlanner 1.x).
Future<List<TransitPlan>> buildTransitPlans(LatLng a, LatLng b) async {
  if (Config.otpUrl.isEmpty) {
    throw Exception('Не задан адрес OpenTripPlanner (lib/config.dart)');
  }
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

/// Ближайшие отправления по GTFS-расписанию через Transitland (нужен ключ).
Future<List<Departure>> loadDepartures(LatLng pos) async {
  if (Config.transitlandKey.isEmpty) return [];
  final stops = await _getJson(Uri.https('transit.land', '/api/v2/rest/stops', {
    'lat': '${pos.latitude}',
    'lon': '${pos.longitude}',
    'radius': '120',
    'limit': '1',
    'apikey': Config.transitlandKey,
  }));
  final list = (stops['stops'] as List?) ?? [];
  if (list.isEmpty) return [];
  final key = Uri.encodeComponent('${list[0]['onestop_id']}');
  final dep = await _getJson(Uri.parse(
      'https://transit.land/api/v2/rest/stops/$key/departures?limit=12&apikey=${Config.transitlandKey}'));
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
