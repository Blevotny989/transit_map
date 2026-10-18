import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'disk_cache.dart';

class TileId {
  final int x, y;
  const TileId(this.x, this.y);
  String get key => '$x/$y';
}

int lonToTileX(double lon, int z) => ((lon + 180) / 360 * (1 << z)).floor();

int latToTileY(double lat, int z) {
  final r = lat.clamp(-85.0, 85.0) * pi / 180;
  return ((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * (1 << z)).floor();
}

double tileXToLon(int x, int z) => x / (1 << z) * 360 - 180;

double tileYToLat(int y, int z) {
  final n = pi - 2 * pi * y / (1 << z);
  return 180 / pi * atan(0.5 * (exp(n) - exp(-n)));
}

/// Данные карты, разбитые на плитки: каждая плитка загружается один раз
/// (сначала ищется на диске), поэтому при движении по городу ничего не перезагружается.
class TileStore<T> {
  TileStore({
    required this.name,
    required this.z,
    required this.clause,
    required this.parse,
    required this.posOf,
    required this.enc,
    required this.dec,
    required this.fetch,
    this.ttl = const Duration(days: 14),
    this.limit = 3000,
  });

  final String name;
  final int z;
  final Duration ttl;
  final int limit;
  final String Function(String bbox) clause;
  final T? Function(Map e) parse;
  final LatLng Function(T) posOf;
  final Map<String, dynamic> Function(T) enc;
  final T Function(Map<String, dynamic>) dec;
  final Future<dynamic> Function(String query) fetch;

  final Map<String, List<T>> mem = {};
  final Set<String> _busy = {};
  void Function()? onChange;

  String _bbox(TileId t) {
    final s = tileYToLat(t.y + 1, z), n = tileYToLat(t.y, z);
    final w = tileXToLon(t.x, z), e = tileXToLon(t.x + 1, z);
    return '$s,$w,$n,$e';
  }

  List<TileId> tilesIn(LatLngBounds b) {
    final x0 = lonToTileX(b.west, z), x1 = lonToTileX(b.east, z);
    final y0 = latToTileY(b.north, z), y1 = latToTileY(b.south, z);
    return [
      for (var x = x0; x <= x1; x++)
        for (var y = y0; y <= y1; y++) TileId(x, y)
    ];
  }

  /// Загруженные объекты в видимой области (не больше [max], ближайшие к центру).
  List<T> visible(LatLngBounds b, {int max = 600}) {
    final out = <T>[];
    for (final t in tilesIn(b)) {
      final l = mem[t.key];
      if (l == null) continue;
      for (final it in l) {
        if (b.contains(posOf(it))) out.add(it);
      }
    }
    if (out.length <= max) return out;
    final c = b.center;
    double d2(T it) {
      final p = posOf(it);
      final dy = p.latitude - c.latitude, dx = p.longitude - c.longitude;
      return dx * dx + dy * dy;
    }

    out.sort((a, b) => d2(a).compareTo(d2(b)));
    return out.sublist(0, max);
  }

  Future<void> ensureBounds(LatLngBounds b, {int maxTiles = 12}) {
    final tiles = tilesIn(b);
    final cx = lonToTileX(b.center.longitude, z), cy = latToTileY(b.center.latitude, z);
    tiles.sort((a, c) {
      final da = (a.x - cx) * (a.x - cx) + (a.y - cy) * (a.y - cy);
      final dc = (c.x - cx) * (c.x - cx) + (c.y - cy) * (c.y - cy);
      return da.compareTo(dc);
    });
    return ensure(tiles.take(maxTiles).toList());
  }

  Future<void> ensure(List<TileId> tiles) async {
    final need = tiles.where((t) => !mem.containsKey(t.key) && !_busy.contains(t.key)).toList();
    if (need.isEmpty) return;
    for (final t in need) {
      _busy.add(t.key);
    }
    try {
      // 1) диск
      final fromDisk = await Future.wait(
          need.map((t) => DiskCache.read('${name}_${z}_${t.x}_${t.y}', ttl)));
      final still = <TileId>[];
      for (var i = 0; i < need.length; i++) {
        final s = fromDisk[i];
        if (s != null) {
          try {
            mem[need[i].key] = [
              for (final m in (jsonDecode(s) as List)) dec(Map<String, dynamic>.from(m as Map))
            ];
            continue;
          } catch (_) {}
        }
        still.add(need[i]);
      }
      if (still.length != need.length) onChange?.call();
      // 2) сеть: ближайшие плитки первой пачкой
      for (var i = 0; i < still.length; i += 8) {
        await _fetchChunk(still.sublist(i, min(i + 8, still.length)));
        onChange?.call();
      }
    } finally {
      for (final t in need) {
        _busy.remove(t.key);
      }
    }
  }

  Future<void> _fetchChunk(List<TileId> chunk) async {
    final sb = StringBuffer('[out:json][timeout:25];(');
    for (final t in chunk) {
      sb.write(clause(_bbox(t)));
    }
    sb.write(');out center $limit;');
    final data = await fetch(sb.toString());
    final byKey = {for (final t in chunk) t.key: <T>[]};
    for (final e in (data['elements'] as List)) {
      final item = parse(Map<String, dynamic>.from(e as Map));
      if (item == null) continue;
      final p = posOf(item);
      byKey['${lonToTileX(p.longitude, z)}/${latToTileY(p.latitude, z)}']?.add(item);
    }
    for (final t in chunk) {
      final list = byKey[t.key]!;
      mem[t.key] = list;
      unawaited(DiskCache.write('${name}_${z}_${t.x}_${t.y}',
          jsonEncode([for (final it in list) enc(it)])));
    }
  }

  void clearMemory() => mem.clear();
}
