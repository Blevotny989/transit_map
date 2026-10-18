import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:latlong2/latlong.dart';
import 'config.dart';
import 'disk_cache.dart';
import 'tile_store.dart';

class CacheStats {
  final int files, bytes;
  const CacheStats(this.files, this.bytes);

  String get human {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} КБ';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} МБ';
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
  }
}

/// HTTP-клиент для плиток карты. Три уровня:
/// 1) память (последние ~100 МБ плиток, отдаются мгновенно),
/// 2) диск (плитки лежат по 256 подпапкам, живут 45 дней и открываются без интернета),
/// 3) сеть: одно постоянное соединение на сервер, одинаковые запросы объединяются.
/// Если сеть недоступна, показываются даже устаревшие плитки с диска.
class TileCacheClient extends http.BaseClient {
  TileCacheClient(this._inner, this._dir, {this.ttl = const Duration(days: 45)});

  final http.Client _inner;
  final Directory _dir;
  final Duration ttl;

  static const _hosts = ['arcgisonline.com', 'arcgis.com', 'openstreetmap.org'];
  static const _memLimit = 100 * 1024 * 1024;

  final LinkedHashMap<String, Uint8List> _mem = LinkedHashMap<String, Uint8List>();
  int _memBytes = 0;
  final Map<String, Future<Uint8List?>> _inflight = {};
  int prefetchEpoch = 0;

  /// Счётчики для проверки, что кэш работает.
  int memHits = 0, diskHits = 0, netLoads = 0;

  static int _fnv(String s) {
    var h = 0x811c9dc5;
    for (final u in s.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  String _key(Uri u) {
    final p = u.path.replaceFirst('/ArcGIS/rest/services/', '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    return '${u.host.split('.').first}_$p';
  }

  /// Снимки со спутника обновляются чаще, чем схема.
  Duration _ttlFor(String key) => key.contains('World_Imagery') ? const Duration(days: 14) : ttl;

  File _file(String key) {
    final shard = (_fnv(key) & 0xFF).toRadixString(16).padLeft(2, '0');
    return File('${_dir.path}${Platform.pathSeparator}$shard${Platform.pathSeparator}$key.tile');
  }

  Future<void> prepareDirs() async {
    try {
      for (var i = 0; i < 256; i++) {
        Directory('${_dir.path}${Platform.pathSeparator}${i.toRadixString(16).padLeft(2, '0')}')
            .createSync(recursive: true);
      }
    } catch (_) {}
  }

  void _put(String key, Uint8List bytes) {
    if (bytes.length > 2 * 1024 * 1024) return;
    final old = _mem.remove(key);
    if (old != null) _memBytes -= old.length;
    _mem[key] = bytes;
    _memBytes += bytes.length;
    while (_memBytes > _memLimit && _mem.isNotEmpty) {
      final k = _mem.keys.first;
      _memBytes -= _mem.remove(k)!.length;
    }
  }

  Future<Uint8List?> _load(String key, Map<String, String> headers, Uri url) async {
    final m = _mem.remove(key);
    if (m != null) {
      _mem[key] = m;
      memHits++;
      return m;
    }
    final f = _file(key);
    Uint8List? stale;
    try {
      final st = await f.stat();
      if (st.type != FileSystemEntityType.notFound) {
        final bytes = await f.readAsBytes();
        if (DateTime.now().difference(st.modified) < _ttlFor(key)) {
          diskHits++;
          _put(key, bytes);
          return bytes;
        }
        stale = bytes;
      }
    } catch (_) {}
    final urls = <Uri>[url];
    // Clarity: самые новые снимки, но покрыты не везде. Если плитки нет, берём обычный World Imagery.
    if (url.host.startsWith('clarity.')) {
      urls.add(Uri.parse('https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/'
          '${url.pathSegments.skip(url.pathSegments.length - 3).join('/')}'));
    }
    for (final u in urls) {
      try {
        final req = http.Request('GET', u)..headers.addAll(headers);
        final resp = await _inner.send(req).timeout(const Duration(seconds: 20));
        if (resp.statusCode == 200) {
          final bytes = await resp.stream.toBytes();
          netLoads++;
          _put(key, bytes);
          unawaited(_write(f, bytes));
          return bytes;
        }
        await resp.stream.drain<void>();
      } catch (_) {}
    }
    if (stale != null) _put(key, stale);
    return stale;
  }

  Future<void> _write(File f, Uint8List bytes) async {
    try {
      await f.writeAsBytes(bytes);
    } catch (_) {}
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    final cacheable = request.method == 'GET' && _hosts.any((h) => u.host.endsWith(h));
    if (!cacheable) return _inner.send(request);
    final key = _key(u);
    final fut = _inflight[key] ??= _load(key, request.headers, u).whenComplete(() {
      _inflight.remove(key);
    });
    final bytes = await fut;
    if (bytes == null) throw http.ClientException('Плитка недоступна', u);
    return http.StreamedResponse(Stream.value(bytes), 200,
        contentLength: bytes.length, request: request, headers: {'content-type': 'image/png'});
  }

  /// Тихая подгрузка плитки в кэш (для соседних масштабов и областей).
  Future<void> prefetchUrl(String url) async {
    try {
      final u = Uri.parse(url);
      final key = _key(u);
      await (_inflight[key] ??= _load(key, {'User-Agent': Config.userAgent}, u).whenComplete(() {
        _inflight.remove(key);
      }));
    } catch (_) {}
  }

  /// Полностью очищает память и диск.
  Future<void> reset() async {
    _mem.clear();
    _memBytes = 0;
    try {
      if (await _dir.exists()) await _dir.delete(recursive: true);
    } catch (_) {}
    try {
      await _dir.create(recursive: true);
    } catch (_) {}
    await prepareDirs();
  }

  /// Удаляет самые старые плитки, если кэш больше лимита.
  Future<void> trim({int maxBytes = 1200 * 1024 * 1024}) async {
    try {
      final items = <_Item>[];
      var total = 0;
      var n = 0;
      await for (final e in _dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final st = await e.stat();
        items.add(_Item(e, st.size, st.modified));
        total += st.size;
        if (++n % 400 == 0) await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      if (total <= maxBytes) return;
      items.sort((a, b) => a.time.compareTo(b.time));
      final goal = (maxBytes * 0.8).round();
      for (final it in items) {
        if (total <= goal) break;
        try {
          await it.file.delete();
          total -= it.size;
        } catch (_) {}
      }
    } catch (_) {}
  }
}

class _Item {
  final File file;
  final int size;
  final DateTime time;
  _Item(this.file, this.size, this.time);
}

TileCacheClient? tileClient;

Future<void> initTileCache() async {
  try {
    final base = await DiskCache.path();
    if (base == null) return;
    final d = Directory('$base${Platform.pathSeparator}tiles');
    await d.create(recursive: true);
    final hc = HttpClient()
      ..maxConnectionsPerHost = 24
      ..idleTimeout = const Duration(seconds: 90)
      ..connectionTimeout = const Duration(seconds: 10);
    final c = TileCacheClient(IOClient(hc), d);
    await c.prepareDirs();
    tileClient = c;
    // Прогрев: соединение с сервером карт открывается ещё на приветственном экране.
    unawaited(c.prefetchUrl('https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/0/0/0'));
    // Уборка старых плиток в фоне, не мешая запуску.
    unawaited(Future<void>.delayed(const Duration(seconds: 40), () => c.trim()));
  } catch (_) {}
}

/// Размер всего кэша на диске (плитки + остановки + города).
Future<CacheStats> cacheStats() async {
  var files = 0, bytes = 0;
  try {
    final base = await DiskCache.path();
    if (base != null) {
      await for (final e in Directory(base).list(recursive: true, followLinks: false)) {
        if (e is File) {
          files++;
          bytes += await e.length();
        }
      }
    }
  } catch (_) {}
  return CacheStats(files, bytes);
}

Future<void> clearAllCaches() async {
  await DiskCache.clear();
  await tileClient?.reset();
}

// ------------------------------------------------------------ подгрузка заранее
/// Заранее кладёт в кэш плитки вокруг [center] на масштабе [z]: при приближении или
/// отдалении карта появляется мгновенно. Прерывается, как только карта снова движется.
Future<void> prefetchTiles(String template, LatLng center, int z, {int radiusX = 2, int radiusY = 1}) async {
  final c = tileClient;
  if (c == null || z < 0 || z > 19) return;
  final epoch = c.prefetchEpoch;
  final n = 1 << z;
  final cx = lonToTileX(center.longitude, z), cy = latToTileY(center.latitude, z);
  final urls = <String>[];
  for (var dy = -radiusY; dy <= radiusY; dy++) {
    for (var dx = -radiusX; dx <= radiusX; dx++) {
      final y = cy + dy;
      if (y < 0 || y >= n) continue;
      final x = ((cx + dx) % n + n) % n;
      urls.add(template.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y'));
    }
  }
  var i = 0;
  Future<void> worker() async {
    while (i < urls.length && c.prefetchEpoch == epoch) {
      await c.prefetchUrl(urls[i++]);
    }
  }

  await Future.wait([for (var k = 0; k < 3; k++) worker()]);
}

void cancelTilePrefetch() {
  final c = tileClient;
  if (c != null) c.prefetchEpoch++;
}
