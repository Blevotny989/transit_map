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
  final Set<String> _stale = {};
  void Function()? onChange;

  /// Сколько плиток сейчас загружается (для индикатора).
  int get pending => _busy.length;

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

  void _sortByCenter(List<TileId> tiles, int cx, int cy) {
    tiles.sort((a, c) {
      final da = (a.x - cx) * (a.x - cx) + (a.y - cy) * (a.y - cy);
      final dc = (c.x - cx) * (c.x - cx) + (c.y - cy) * (c.y - cy);
      return da.compareTo(dc);
    });
  }

  Future<void> ensureBounds(LatLngBounds b, {int maxTiles = 12}) {
    final tiles = tilesIn(b);
    _sortByCenter(tiles, lonToTileX(b.center.longitude, z), latToTileY(b.center.latitude, z));
    return ensure(tiles.take(maxTiles).toList());
  }

  /// Тихо подгружает «кольцо» плиток вокруг экрана, чтобы при прокрутке всё уже было готово.
  Future<void> ensureRing(LatLngBounds b, {int ring = 1, int maxTiles = 16}) {
    final x0 = lonToTileX(b.west, z), x1 = lonToTileX(b.east, z);
    final y0 = latToTileY(b.north, z), y1 = latToTileY(b.south, z);
    final tiles = <TileId>[];
    for (var x = x0 - ring; x <= x1 + ring; x++) {
      for (var y = y0 - ring; y <= y1 + ring; y++) {
        if (x >= x0 && x <= x1 && y >= y0 && y <= y1) continue;
        tiles.add(TileId(x, y));
      }
    }
    _sortByCenter(tiles, lonToTileX(b.center.longitude, z), latToTileY(b.center.latitude, z));
    return ensure(tiles.take(maxTiles).toList(), quiet: true);
  }

  List<T> _decode(String s) => [
        for (final m in (jsonDecode(s) as List)) dec(Map<String, dynamic>.from(m as Map))
      ];

  Future<void> ensure(List<TileId> tiles, {bool quiet = false}) async {
    final need = tiles
        .where((t) => !_busy.contains(t.key) && (!mem.containsKey(t.key) || _stale.contains(t.key)))
        .toList();
    if (need.isEmpty) return;
    for (final t in need) {
      _busy.add(t.key);
    }
    try {
      // 1) диск: свежее показываем сразу, устаревшее тоже, но потом обновляем из сети
      final reads = await Future.wait(need.map((t) => mem.containsKey(t.key)
          ? Future<CacheHit?>.value(null)
          : DiskCache.readHit('${name}_${z}_${t.x}_${t.y}')));
      final fetchList = <TileId>[];
      var shown = false;
      for (var i = 0; i < need.length; i++) {
        final t = need[i];
        final hit = reads[i];
        if (hit != null) {
          try {
            mem[t.key] = _decode(hit.data);
            shown = true;
            if (hit.age < ttl) {
              _stale.remove(t.key);
              continue;
            }
            _stale.add(t.key);
          } catch (_) {}
        }
        fetchList.add(t);
      }
      if (shown) onChange?.call();
      // 2) сеть: небольшие порции, несколько запросов одновременно, ближайшие плитки первыми
      final chunks = <List<TileId>>[];
      for (var i = 0; i < fetchList.length; i += 4) {
        chunks.add(fetchList.sublist(i, min(i + 4, fetchList.length)));
      }
      var next = 0;
      Object? lastError;
      Future<void> worker() async {
        while (next < chunks.length) {
          final ch = chunks[next++];
          try {
            await _fetchChunk(ch);
          } catch (e) {
            lastError = e;
          }
          onChange?.call();
        }
      }

      final workers = min(quiet ? 2 : 4, chunks.length);
      await Future.wait([for (var k = 0; k < workers; k++) worker()]);
      if (!quiet && lastError != null && fetchList.any((t) => !mem.containsKey(t.key))) {
        throw lastError!;
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
      _stale.remove(t.key);
      unawaited(DiskCache.write('${name}_${z}_${t.x}_${t.y}',
          jsonEncode([for (final it in list) enc(it)])));
    }
  }

  void clearMemory() {
    mem.clear();
    _stale.clear();
  }
}
