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

class RouteInfo {
  final String mode, ref, name, from, to, operator;
  RouteInfo(this.mode, this.ref, this.name, this.from, this.to, this.operator);
}

class Place {
  final String name;
  final LatLng pos;
  Place(this.name, this.pos);
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
