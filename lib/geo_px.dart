import 'dart:math' as math;

/// Проекция Web Mercator в пиксели мира (плитки 256 px). Нужна, чтобы рисовать
/// остановки и подписи прямо на холсте, не создавая тысячи виджетов.
double worldSize(double zoom) => 256.0 * math.pow(2.0, zoom).toDouble();

double lonToPx(double lon, double zoom) => (lon + 180.0) / 360.0 * worldSize(zoom);

double latToPx(double lat, double zoom) {
  final l = lat.clamp(-85.0511, 85.0511).toDouble();
  final s = math.sin(l * math.pi / 180.0);
  return (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * worldSize(zoom);
}

double pxToLon(double x, double zoom) => x / worldSize(zoom) * 360.0 - 180.0;

double pxToLat(double y, double zoom) {
  final n = math.pi - 2 * math.pi * y / worldSize(zoom);
  return 180.0 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
}
