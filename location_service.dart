import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

enum LocStatus { ok, serviceOff, denied, deniedForever, timeout, error }

class LocFix {
  final LatLng pos;
  final double accuracy;
  final bool approximate;
  final String? place;
  const LocFix(this.pos, this.accuracy, {this.approximate = false, this.place});
}

class LocResult {
  final LocStatus status;
  final LocFix? fix;
  const LocResult(this.status, {this.fix});
}

/// Определение положения: сначала система (Windows: Wi-Fi/GPS, после разрешения),
/// если не вышло, примерное положение по IP-адресу.
class LocationService {
  static LocFix? last;
  static StreamSubscription<Position>? _sub;

  static Future<LocResult> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return const LocResult(LocStatus.serviceOff);
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.deniedForever) return const LocResult(LocStatus.deniedForever);
      if (perm == LocationPermission.denied) return const LocResult(LocStatus.denied);
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
      );
      final fix = LocFix(LatLng(p.latitude, p.longitude), p.accuracy);
      last = fix;
      return LocResult(LocStatus.ok, fix: fix);
    } on TimeoutException {
      return const LocResult(LocStatus.timeout);
    } catch (_) {
      return const LocResult(LocStatus.error);
    }
  }

  /// Открывает раздел «Расположение» в параметрах Windows.
  static Future<void> openSettings() async {
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
  }

  /// Примерное положение по IP (точность порядка города).
  static Future<LocFix?> byIp() async {
    Future<LocFix?> geojs() async {
      final r = await http.get(Uri.parse('https://get.geojs.io/v1/ip/geo.json')).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final la = double.tryParse('${j['latitude']}'), lo = double.tryParse('${j['longitude']}');
      if (la == null || lo == null) return null;
      return LocFix(LatLng(la, lo), 8000, approximate: true, place: '${j['city'] ?? ''}'.trim());
    }

    Future<LocFix?> ipwho() async {
      final r = await http.get(Uri.parse('https://ipwho.is/')).timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map;
      final la = (j['latitude'] as num?)?.toDouble(), lo = (j['longitude'] as num?)?.toDouble();
      if (la == null || lo == null) return null;
      return LocFix(LatLng(la, lo), 8000, approximate: true, place: '${j['city'] ?? ''}'.trim());
    }

    for (final f in [geojs, ipwho]) {
      try {
        final r = await f();
        if (r != null) {
          last = r;
          return r;
        }
      } catch (_) {}
    }
    return null;
  }

  /// Следит за перемещением: синяя точка на карте обновляется сама.
  static void startWatching(void Function(LocFix) onFix) {
    _sub?.cancel();
    try {
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15),
      ).listen((p) {
        final f = LocFix(LatLng(p.latitude, p.longitude), p.accuracy);
        last = f;
        onFix(f);
      }, onError: (Object _) {});
    } catch (_) {}
  }

  static void stopWatching() {
    _sub?.cancel();
    _sub = null;
  }
}
