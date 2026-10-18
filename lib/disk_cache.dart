import 'dart:io';

/// Простой кэш на диске: остановки и города загружаются один раз и потом открываются мгновенно.
class DiskCache {
  static Directory? _dir;

  static Future<Directory?> _d() async {
    if (_dir != null) return _dir;
    try {
      final env = Platform.environment;
      final base = env['LOCALAPPDATA'] ??
          env['XDG_CACHE_HOME'] ??
          (env['HOME'] != null ? '${env['HOME']}/.cache' : Directory.systemTemp.path);
      final d = Directory('$base${Platform.pathSeparator}transit_map_cache');
      await d.create(recursive: true);
      _dir = d;
      return d;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> path() async => (await _d())?.path;

  static String _safe(String n) => n.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  static Future<String?> read(String name, Duration ttl) async {
    try {
      final d = await _d();
      if (d == null) return null;
      final f = File('${d.path}${Platform.pathSeparator}${_safe(name)}.json');
      if (!await f.exists()) return null;
      final age = DateTime.now().difference(await f.lastModified());
      if (age > ttl) return null;
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String name, String data) async {
    try {
      final d = await _d();
      if (d == null) return;
      await File('${d.path}${Platform.pathSeparator}${_safe(name)}.json').writeAsString(data);
    } catch (_) {}
  }

  static Future<void> clear() async {
    try {
      final d = await _d();
      if (d != null && await d.exists()) {
        await d.delete(recursive: true);
        _dir = null;
      }
    } catch (_) {}
  }
}
