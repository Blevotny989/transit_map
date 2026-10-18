import 'dart:io';
import 'package:http/http.dart' as http;
import 'disk_cache.dart';

/// HTTP-клиент для плиток карты с кэшем на диске: просмотренные места открываются мгновенно
/// и без интернета. Радар осадков не кэшируется.
class TileCacheClient extends http.BaseClient {
  TileCacheClient(this._inner, this._dir, {this.ttl = const Duration(days: 30)});

  final http.Client _inner;
  final Directory _dir;
  final Duration ttl;

  static const _hosts = ['arcgisonline.com', 'openstreetmap.org'];

  File _file(Uri u) {
    final p = u.path.replaceFirst('/ArcGIS/rest/services/', '').replaceAll(RegExp(r'[^A-Za-z0-9]'), '_');
    return File('${_dir.path}${Platform.pathSeparator}${u.host.split('.').first}_$p.tile');
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final u = request.url;
    final cacheable = request.method == 'GET' && _hosts.any((h) => u.host.endsWith(h));
    if (cacheable) {
      try {
        final f = _file(u);
        if (await f.exists() && DateTime.now().difference(await f.lastModified()) < ttl) {
          final bytes = await f.readAsBytes();
          return http.StreamedResponse(Stream.value(bytes), 200,
              contentLength: bytes.length, request: request, headers: {'content-type': 'image/png'});
        }
      } catch (_) {}
    }
    final resp = await _inner.send(request);
    if (cacheable && resp.statusCode == 200) {
      final bytes = await resp.stream.toBytes();
      try {
        await _file(u).writeAsBytes(bytes);
      } catch (_) {}
      return http.StreamedResponse(Stream.value(bytes), 200,
          contentLength: bytes.length,
          request: request,
          headers: resp.headers,
          reasonPhrase: resp.reasonPhrase);
    }
    return resp;
  }
}

TileCacheClient? tileClient;

Future<void> initTileCache() async {
  try {
    final base = await DiskCache.path();
    if (base == null) return;
    final d = Directory('$base${Platform.pathSeparator}tiles');
    await d.create(recursive: true);
    tileClient = TileCacheClient(http.Client(), d);
  } catch (_) {}
}
