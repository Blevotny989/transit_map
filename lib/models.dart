import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum StopKind { bus, tram, train, subway, ferry }

extension StopKindX on StopKind {
  String get label => switch (this) {
        StopKind.bus => 'Автобус',
        StopKind.tram => 'Трамвай',
        StopKind.train => 'Ж/д станция',
        StopKind.subway => 'Метро',
        StopKind.ferry => 'Паром',
      };

  IconData get icon => switch (this) {
        StopKind.bus => Icons.directions_bus,
        StopKind.tram => Icons.tram,
        StopKind.train => Icons.train,
        StopKind.subway => Icons.subway,
        StopKind.ferry => Icons.directions_boat,
      };

  Color get color => switch (this) {
        StopKind.bus => const Color(0xFF1E6FD9),
        StopKind.tram => const Color(0xFFD97B1E),
        StopKind.train => const Color(0xFF2E8B57),
        StopKind.subway => const Color(0xFF8E44AD),
        StopKind.ferry => const Color(0xFF0097A7),
      };
}

class Stop {
  final int id;
  final LatLng pos;
  final String name;
  final StopKind kind;
  final Map<String, String> tags;
  Stop(this.id, this.pos, this.name, this.kind, this.tags);

  static StopKind kindFromTags(Map<String, String> t) {
    if (t['amenity'] == 'ferry_terminal') return StopKind.ferry;
    if (t['railway'] == 'tram_stop') return StopKind.tram;
    if (t['station'] == 'subway' || t['subway'] == 'yes') return StopKind.subway;
    if (t['railway'] == 'station' || t['railway'] == 'halt') return StopKind.train;
    return StopKind.bus;
  }
}

/// Город, посёлок, деревня или хутор на карте.
class PlaceDot {
  final String name;
  final LatLng pos;
  final String kind; // city, town, village, hamlet
  final int? population;
  PlaceDot(this.name, this.pos, this.kind, this.population);
}

class RouteInfo {
  final int id;
  final String mode, ref, name, from, to, operator, interval, hours;
  RouteInfo(this.id, this.mode, this.ref, this.name, this.from, this.to, this.operator,
      this.interval, this.hours);
}

String modeRu(String m) => switch (m) {
      'bus' => 'Автобус',
      'trolleybus' => 'Троллейбус',
      'tram' => 'Трамвай',
      'train' => 'Поезд',
      'subway' => 'Метро',
      'light_rail' => 'Легкорельсовый',
      'ferry' => 'Паром',
      'monorail' => 'Монорельс',
      _ => m,
    };

class Place {
  final String name;
  final LatLng pos;
  final String subtitle;
  Place(this.name, this.pos, [this.subtitle = '']);
}

/// Краткая сводка об объекте на карте.
class ObjectInfo {
  final String title, typeLabel, address;
  final List<MapEntry<String, String>> facts;
  final String? wikiText, wikiImage, wikiUrl;
  ObjectInfo(this.title, this.typeLabel, this.address, this.facts,
      {this.wikiText, this.wikiImage, this.wikiUrl});
}

enum MapBase { scheme, topo, dark, osm, satellite, hybrid }

extension MapBaseX on MapBase {
  String get label => switch (this) {
        MapBase.scheme => 'Схема',
        MapBase.topo => 'Рельеф',
        MapBase.dark => 'Тёмная',
        MapBase.osm => 'OSM',
        MapBase.satellite => 'Спутник',
        MapBase.hybrid => 'Гибрид',
      };
  IconData get icon => switch (this) {
        MapBase.scheme => Icons.map_outlined,
        MapBase.topo => Icons.terrain,
        MapBase.dark => Icons.dark_mode_outlined,
        MapBase.osm => Icons.public,
        MapBase.satellite => Icons.satellite_alt,
        MapBase.hybrid => Icons.layers,
      };
}

enum RouteMode { walk, car, bike, transit }

extension RouteModeX on RouteMode {
  String get label => switch (this) {
        RouteMode.walk => 'Пешком',
        RouteMode.car => 'Авто',
        RouteMode.bike => 'Велосипед',
        RouteMode.transit => 'Транспорт',
      };
  Color get color => switch (this) {
        RouteMode.walk => const Color(0xFF2E9E5B),
        RouteMode.car => const Color(0xFF1E6FD9),
        RouteMode.bike => const Color(0xFFEF8A17),
        RouteMode.transit => const Color(0xFF8E44AD),
      };
  IconData get icon => switch (this) {
        RouteMode.walk => Icons.directions_walk,
        RouteMode.car => Icons.directions_car,
        RouteMode.bike => Icons.directions_bike,
        RouteMode.transit => Icons.directions_transit,
      };
}

class RouteResult {
  final List<LatLng> points;
  final double meters;
  final double seconds;
  RouteResult(this.points, this.meters, this.seconds);
}

class TransitLeg {
  final String mode, route, from, to;
  final double seconds;
  final List<LatLng> points;
  final int stops;
  final double waitSeconds;
  TransitLeg(this.mode, this.route, this.from, this.to, this.seconds, this.points,
      {this.stops = 0, this.waitSeconds = 0});
}

class TransitPlan {
  final double seconds;
  final List<TransitLeg> legs;
  final bool estimated;
  TransitPlan(this.seconds, this.legs, {this.estimated = false});

  int get transfers {
    final n = legs.where((l) => l.mode != 'WALK').length;
    return n > 0 ? n - 1 : 0;
  }
}

String legModeFor(String osm) => switch (osm) {
      'bus' => 'BUS',
      'trolleybus' => 'TROLLEYBUS',
      'tram' => 'TRAM',
      'light_rail' => 'TRAM',
      'subway' => 'SUBWAY',
      'monorail' => 'SUBWAY',
      'train' => 'RAIL',
      'ferry' => 'FERRY',
      _ => 'BUS',
    };

String legModeRu(String m) => switch (m) {
      'WALK' => 'Пешком',
      'BUS' => 'Автобус',
      'TROLLEYBUS' => 'Троллейбус',
      'TRAM' => 'Трамвай',
      'SUBWAY' => 'Метро',
      'RAIL' => 'Поезд',
      'FERRY' => 'Паром',
      _ => m,
    };

IconData legIcon(String m) => switch (m) {
      'WALK' => Icons.directions_walk,
      'TRAM' => Icons.tram,
      'SUBWAY' => Icons.subway,
      'RAIL' => Icons.train,
      'FERRY' => Icons.directions_boat,
      _ => Icons.directions_bus,
    };

Color legColor(String m) => switch (m) {
      'WALK' => const Color(0xFF2E9E5B),
      'TRAM' => const Color(0xFFD97B1E),
      'SUBWAY' => const Color(0xFF8E44AD),
      'RAIL' => const Color(0xFF2E8B57),
      'FERRY' => const Color(0xFF0097A7),
      _ => const Color(0xFF1E6FD9),
    };

/// Остановка на линии маршрута (для самостоятельного подбора пересадок).
class StopPt {
  final int id;
  final LatLng pos;
  final String name;
  StopPt(this.id, this.pos, this.name);
}

class RadarFrame {
  final String path;
  final int time;
  final bool nowcast;
  RadarFrame(this.path, this.time, this.nowcast);
}

class RadarData {
  final String host;
  final List<RadarFrame> frames;
  final int currentIndex;
  RadarData(this.host, this.frames, this.currentIndex);
}

class WeatherHour {
  final String hour;
  final double temp, prob, precip;
  final int code;
  WeatherHour(this.hour, this.temp, this.prob, this.precip, this.code);
}

class WeatherInfo {
  final double temp, feels, humidity, wind, pressureMm, cloud, precip;
  final int code;
  final List<WeatherHour> hours;
  final double daySum, dayProb, tMax, tMin;
  final String? nowcast;
  WeatherInfo({
    required this.temp,
    required this.feels,
    required this.humidity,
    required this.wind,
    required this.pressureMm,
    required this.cloud,
    required this.precip,
    required this.code,
    required this.hours,
    required this.daySum,
    required this.dayProb,
    required this.tMax,
    required this.tMin,
    this.nowcast,
  });
}

class WeatherDesc {
  final String label;
  final IconData icon;
  final List<Color> colors;
  const WeatherDesc(this.label, this.icon, this.colors);
}

WeatherDesc weatherDesc(int c) {
  if (c == 0) return const WeatherDesc('Ясно', Icons.wb_sunny, [Color(0xFF29B6F6), Color(0xFF1565C0)]);
  if (c == 1) return const WeatherDesc('Малооблачно', Icons.wb_sunny, [Color(0xFF4FC3F7), Color(0xFF1976D2)]);
  if (c == 2) return const WeatherDesc('Переменная облачность', Icons.wb_cloudy, [Color(0xFF64B5F6), Color(0xFF546E7A)]);
  if (c == 3) return const WeatherDesc('Пасмурно', Icons.cloud, [Color(0xFF90A4AE), Color(0xFF455A64)]);
  if (c == 45 || c == 48) return const WeatherDesc('Туман', Icons.cloud, [Color(0xFFB0BEC5), Color(0xFF78909C)]);
  if (c >= 51 && c <= 57) return const WeatherDesc('Морось', Icons.grain, [Color(0xFF78909C), Color(0xFF37474F)]);
  if (c >= 61 && c <= 65) return const WeatherDesc('Дождь', Icons.water_drop, [Color(0xFF546E7A), Color(0xFF1A237E)]);
  if (c == 66 || c == 67) return const WeatherDesc('Ледяной дождь', Icons.water_drop, [Color(0xFF607D8B), Color(0xFF283593)]);
  if (c >= 71 && c <= 77) return const WeatherDesc('Снег', Icons.ac_unit, [Color(0xFF90A4AE), Color(0xFF5C6BC0)]);
  if (c >= 80 && c <= 82) return const WeatherDesc('Ливень', Icons.water_drop, [Color(0xFF455A64), Color(0xFF0D47A1)]);
  if (c == 85 || c == 86) return const WeatherDesc('Снегопад', Icons.ac_unit, [Color(0xFF78909C), Color(0xFF3949AB)]);
  if (c >= 95) return const WeatherDesc('Гроза', Icons.bolt, [Color(0xFF5E35B1), Color(0xFF311B92)]);
  return const WeatherDesc('Облачно', Icons.cloud, [Color(0xFF90A4AE), Color(0xFF546E7A)]);
}

class Departure {
  final String time, route, headsign;
  Departure(this.time, this.route, this.headsign);
}

String fmtDuration(double sec) {
  final m = (sec / 60).round();
  if (m < 60) return '$m мин';
  return '${m ~/ 60} ч ${m % 60} мин';
}

String fmtDistance(double m) =>
    m < 1000 ? '${m.round()} м' : '${(m / 1000).toStringAsFixed(1)} км';
