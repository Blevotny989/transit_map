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

enum MapBase { scheme, dark, osm, satellite, hybrid }

extension MapBaseX on MapBase {
  String get label => switch (this) {
        MapBase.scheme => 'Схема',
        MapBase.dark => 'Тёмная',
        MapBase.osm => 'OSM',
        MapBase.satellite => 'Спутник',
        MapBase.hybrid => 'Гибрид',
      };
  IconData get icon => switch (this) {
        MapBase.scheme => Icons.map_outlined,
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
  TransitLeg(this.mode, this.route, this.from, this.to, this.seconds, this.points);
}

class TransitPlan {
  final double seconds;
  final List<TransitLeg> legs;
  TransitPlan(this.seconds, this.legs);
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
