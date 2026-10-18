import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'app_theme.dart';
import 'boot.dart';
import 'config.dart';
import 'info_sheet.dart';
import 'location_service.dart';
import 'models.dart';
import 'place_picker.dart';
import 'providers.dart';
import 'sea_lore.dart';
import 'services.dart';
import 'settings_dialog.dart';
import 'stop_sheet.dart';
import 'stops_layer.dart';
import 'tile_cache.dart';
import 'vintage_overlay.dart';

/// Слой подложки: шаблон адреса плиток и максимальный масштаб, на котором они есть.
class _Layer {
  final String url;
  final int maxZoom;
  _Layer(this.url, [this.maxZoom = 19]);
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _esri = 'https://server.arcgisonline.com/ArcGIS/rest/services';

  final _map = MapController();
  final _searchCtrl = TextEditingController();
  Timer? _fetchTimer, _idleTimer, _saveTimer, _searchDebounce, _radarTimer;
  late final TileProvider _tileProvider;
  bool _mapReady = false;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);

  // карта
  MapBase _base = MapBase.scheme;
  final Set<StopKind> _kinds = {...StopKind.values};
  bool _loading = false;
  String? _hint;
  bool _userMoved = false, _hadSavedView = false, _bootDone = false, _locating = false;
  double _meAcc = 0;
  bool _meApprox = false;

  // радар
  bool _radarOn = false;
  bool _radarPlaying = true;
  RadarData? _radar;
  int _radarIdx = 0;

  // поиск
  List<Place> _found = [];
  bool _searching = false;
  int _searchSeq = 0;

  // точки и маршрут
  LatLng? _me, _from, _to, _pin;
  String _fromName = '', _toName = '';
  int _picking = 0; // 0 нет, 1 «откуда», 2 «куда»
  bool _routeOpen = false;
  RouteMode _mode = RouteMode.walk;
  RouteResult? _result;
  bool _estimate = false;
  List<TransitPlan> _plans = [];
  int _planIdx = 0;
  String? _routeError;
  bool _routing = false;
  int _gen = 0, _applyN = 0;
  Map<RouteMode, Future<RouteResult>> _rf = {};
  Future<List<TransitPlan>>? _transitFuture;
  Map<RouteMode, double> _modeSecs = {};

  // линия выбранного маршрута транспорта
  List<List<LatLng>> _lineRoute = [];
  String? _lineLabel;

  @override
  void initState() {
    super.initState();
    _base = MapBase.values.firstWhere((b) => b.name == Config.baseName, orElse: () => MapBase.scheme);
    _hadSavedView = Config.lastLat != null && Config.lastLon != null;
    _tileProvider = NetworkTileProvider(httpClient: tileClient);
    stopStore.onChange = _refreshVisible;
    stationStore.onChange = _refreshVisible;
    bigPlaceStore.onChange = _refreshVisible;
    smallPlaceStore.onChange = _refreshVisible;
  }

  @override
  void dispose() {
    stopStore.onChange = null;
    stationStore.onChange = null;
    bigPlaceStore.onChange = null;
    smallPlaceStore.onChange = null;
    _fetchTimer?.cancel();
    _idleTimer?.cancel();
    _saveTimer?.cancel();
    _searchDebounce?.cancel();
    _radarTimer?.cancel();
    LocationService.stopWatching();
    _repaint.dispose();
    super.dispose();
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _bootReady() {
    if (_bootDone) return;
    _bootDone = true;
    Boot.done();
  }

  // ------------------------------------------------ загрузка объектов карты
  void _onMove(MapCamera cam, bool gesture) {
    if (gesture) _userMoved = true;
    cancelTilePrefetch();
    _fetchTimer?.cancel();
    _fetchTimer = Timer(const Duration(milliseconds: 140), _fetch);
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(milliseconds: 1000), _prefetchAround);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || !_mapReady) return;
      final c = _map.camera;
      Config.lastLat = c.center.latitude;
      Config.lastLon = c.center.longitude;
      Config.lastZoom = c.zoom;
      Config.saveView();
    });
  }

  /// Остановки и города рисуются прямо на холсте и сами следуют за картой;
  /// здесь только просим перерисовать и обновляем индикатор загрузки.
  void _refreshVisible() {
    if (!mounted) return;
    _repaint.value++;
    final busy = stopStore.pending + stationStore.pending + bigPlaceStore.pending + smallPlaceStore.pending > 0;
    if (busy != _loading) setState(() => _loading = busy);
  }

  bool _anyStops(LatLngBounds vb) => stopStore.visible(vb, max: 3000).any((s) => _kinds.contains(s.kind));

  Future<void> _fetch() async {
    if (!_mapReady || !mounted) return;
    final cam = _map.camera;
    final z = cam.zoom, vb = cam.visibleBounds;
    String? hint;
    if (z < 8) {
      hint = 'Приблизьте карту, чтобы увидеть города';
    } else if (z < Config.minStationsZoom) {
      hint = 'Приблизьте карту, чтобы увидеть станции';
    } else if (z < Config.minStopsZoom) {
      hint = 'Приблизьте карту ещё немного, чтобы увидеть остановки';
    }
    if (hint != _hint) setState(() => _hint = hint);
    _refreshVisible();
    if (z < 8) {
      _bootReady();
      return;
    }
    try {
      final fs = <Future<void>>[];
      if (z >= Config.minStopsZoom) {
        fs.add(stopStore.ensureBounds(vb, maxTiles: 40));
      } else {
        fs.add(bigPlaceStore.ensureBounds(vb, maxTiles: 12));
        if (z >= 10) fs.add(smallPlaceStore.ensureBounds(vb, maxTiles: 9));
        if (z >= Config.minStationsZoom) fs.add(stationStore.ensureBounds(vb, maxTiles: 9));
      }
      await Future.wait(fs);
      _refreshVisible();
      if (mounted && z >= Config.minStopsZoom && stopStore.pending == 0 && !_anyStops(vb)) {
        setState(() => _hint = 'В этой области остановок в OpenStreetMap нет');
      }
    } catch (_) {
      if (mounted) setState(() => _hint = 'Не удалось загрузить данные, попробуйте ещё раз');
    } finally {
      _bootReady();
    }
  }

  /// Когда карта остановилась: тихо подгружаем соседние области и соседние масштабы,
  /// чтобы сдвиг и приближение показывались без ожидания.
  Future<void> _prefetchAround() async {
    if (!mounted || !_mapReady) return;
    final cam = _map.camera;
    final z = cam.zoom, vb = cam.visibleBounds;
    try {
      if (z >= Config.minStopsZoom) {
        await stopStore.ensureRing(vb, maxTiles: 18);
      } else if (z >= 8) {
        await bigPlaceStore.ensureRing(vb, maxTiles: 8);
      }
    } catch (_) {}
    if (!mounted) return;
    final zi = z.floor();
    for (final dz in const [1, -1]) {
      final tz = zi + dz;
      for (final sp in _baseSpecs(_base)) {
        if (tz < 1 || tz > sp.maxZoom) continue;
        unawaited(prefetchTiles(sp.url, cam.center, tz, radiusX: dz > 0 ? 2 : 1, radiusY: dz > 0 ? 1 : 0));
      }
    }
  }

  // ------------------------------------------------------------------ поиск
  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _found = []);
      return;
    }
    final ms = photonLangs.contains(Config.lang) ? 350 : 550;
    _searchDebounce = Timer(Duration(milliseconds: ms), () => _search(q, auto: true));
  }

  Future<void> _search(String q, {bool auto = false}) async {
    if (q.trim().isEmpty) return;
    if (!auto) FocusScope.of(context).unfocus();
    final seq = ++_searchSeq;
    setState(() => _searching = true);
    try {
      final r = await searchPlaces(q.trim(), _map.camera.center);
      if (!mounted || seq != _searchSeq) return;
      setState(() => _found = r);
      if (r.isEmpty && !auto) _snack('Ничего не найдено');
    } catch (_) {
      if (!auto && mounted) _snack('Поиск не удался, проверьте интернет');
    } finally {
      if (mounted && seq == _searchSeq) setState(() => _searching = false);
    }
  }

  void _openFound(Place p) {
    _map.move(p.pos, 15);
    setState(() {
      _found = [];
      _pin = p.pos;
    });
    _showInfo(p.pos, hint: p.name);
  }

  void _applyFix(LocFix f, {required bool move}) {
    if (!mounted) return;
    setState(() {
      _me = f.pos;
      _meAcc = f.accuracy;
      _meApprox = f.approximate;
    });
    if (move) _map.move(f.pos, f.approximate ? 11.0 : 16.0);
  }

  /// Положение: Windows спрашивает разрешение, карта использует ответ.
  /// При запуске ([auto]) никаких окон: если нельзя, тихо берём примерное место по IP.
  Future<void> _locate({bool move = true, bool auto = false}) async {
    if (_locating) return;
    _locating = true;
    try {
      final r = await LocationService.locate();
      if (!mounted) return;
      final fix = r.fix;
      if (fix != null) {
        _applyFix(fix, move: auto ? (!_userMoved && !_hadSavedView) : move);
        LocationService.startWatching((f) {
          if (!mounted) return;
          setState(() {
            _me = f.pos;
            _meAcc = f.accuracy;
            _meApprox = false;
          });
        });
        return;
      }
      if (auto) {
        final ip = await LocationService.byIp();
        if (ip != null) _applyFix(ip, move: !_userMoved && !_hadSavedView);
        return;
      }
      await _explainLocation(r.status, move);
    } finally {
      _locating = false;
    }
  }

  Future<void> _explainLocation(LocStatus st, bool move) async {
    final String msg;
    if (st == LocStatus.timeout) {
      msg = 'Windows не успел определить положение. На компьютере без GPS оно определяется по Wi-Fi '
          'и может занять время. Попробуйте ещё раз.';
    } else if (st == LocStatus.error) {
      msg = 'Не удалось определить положение.';
    } else {
      msg = 'Windows не разрешает программе узнать ваше положение.\n\n'
          'Откройте «Параметры → Конфиденциальность и защита → Расположение», включите «Службы определения '
          'расположения» и «Разрешить классическим приложениям доступ к вашему расположению», затем нажмите '
          'кнопку положения ещё раз.';
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Положение не определено'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'close'), child: const Text('Закрыть')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'ip'), child: const Text('Примерно, по IP')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'settings'), child: const Text('Открыть параметры')),
        ],
      ),
    );
    if (!mounted) return;
    if (choice == 'settings') {
      await LocationService.openSettings();
    } else if (choice == 'ip') {
      final ip = await LocationService.byIp();
      if (!mounted) return;
      if (ip == null) {
        _snack('Не удалось определить положение по IP');
      } else {
        _applyFix(ip, move: move);
        final place = ip.place;
        _snack(place != null && place.isNotEmpty ? 'Примерное положение: $place' : 'Показано примерное положение');
      }
    }
  }

  void _showLore(LoreItem it) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(it.title),
        content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Text(it.text)),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть'))],
      ),
    );
  }

  // ---------------------------------------------------------- сводка объекта
  void _showInfo(LatLng p, {String? hint}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => InfoSheet(
        pos: p,
        zoom: _map.camera.zoom,
        hintTitle: hint,
        onFrom: (name) {
          Navigator.pop(context);
          _setFrom(p, name);
        },
        onTo: (name) {
          Navigator.pop(context);
          _setTo(p, name);
        },
      ),
    );
  }

  void _openStop(Stop s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => StopSheet(
        stop: s,
        onFrom: () {
          Navigator.pop(context);
          _setFrom(s.pos, s.name);
        },
        onTo: () {
          Navigator.pop(context);
          _setTo(s.pos, s.name);
        },
        onShowRoute: (r) {
          Navigator.pop(context);
          _showLine(r);
        },
      ),
    );
  }

  Future<void> _showLine(RouteInfo r) async {
    try {
      final g = await loadRouteGeometry(r.id);
      if (g.isEmpty) {
        _snack('Для этого маршрута в OpenStreetMap нет линии');
        return;
      }
      final dir = r.from.isNotEmpty ? '${r.from} → ${r.to}' : r.name;
      setState(() {
        _lineRoute = g;
        _lineLabel = '${modeRu(r.mode)} ${r.ref} $dir'.trim();
      });
      final pts = g.expand((e) => e).toList();
      _map.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(70)));
    } catch (_) {
      _snack('Не удалось загрузить линию маршрута');
    }
  }

  // ----------------------------------------------------------------- маршрут
  void _setFrom(LatLng p, String name) {
    setState(() {
      _from = p;
      _fromName = name;
      _routeOpen = true;
    });
    _buildRoute();
  }

  void _setTo(LatLng p, String name) {
    setState(() {
      _to = p;
      _toName = name;
      _routeOpen = true;
    });
    _buildRoute();
  }

  Future<void> _editPoint(bool isFrom) async {
    final r = await showPlacePicker(context, _map.camera.center);
    if (r == null) return;
    if (r.onMap) {
      setState(() => _picking = isFrom ? 1 : 2);
      return;
    }
    if (r.useMe) {
      await _locate(move: false);
      if (_me == null) return;
      isFrom ? _setFrom(_me!, 'Моё положение') : _setTo(_me!, 'Моё положение');
      return;
    }
    final p = r.place;
    if (p == null) return;
    isFrom ? _setFrom(p.pos, p.name) : _setTo(p.pos, p.name);
  }

  void _swap() {
    final f = _from ?? _me;
    final fn = _from == null ? 'Моё положение' : _fromName;
    setState(() {
      _from = _to;
      _fromName = _toName;
      _to = f;
      _toName = fn;
    });
    _buildRoute();
  }

  void _closeRoute() {
    _gen++;
    _applyN++;
    setState(() {
      _routeOpen = false;
      _from = _to = null;
      _result = null;
      _plans = [];
      _routeError = null;
      _estimate = false;
      _routing = false;
      _rf = {};
      _transitFuture = null;
      _modeSecs = {};
    });
  }

  /// Считает сразу пешком, авто, велосипед и транспорт: время каждого режима видно на вкладках,
  /// а переключение между ними мгновенное. Остановки вдоль пути подгружаются заранее.
  Future<void> _buildRoute() async {
    final a = _from ?? _me;
    final b = _to;
    final gen = ++_gen;
    setState(() {
      _result = null;
      _plans = [];
      _planIdx = 0;
      _routeError = null;
      _estimate = false;
      _routing = false;
      _rf = {};
      _transitFuture = null;
      _modeSecs = {};
    });
    if (a == null || b == null) return;
    for (final m in [RouteMode.walk, RouteMode.car, RouteMode.bike]) {
      final f = buildRoute(a, b, m);
      _rf[m] = f;
      f.then((r) {
        if (!mounted || gen != _gen) return;
        setState(() => _modeSecs[m] = r.seconds);
        if (m == RouteMode.car) unawaited(prefetchStopsAlong(r.points));
      }, onError: (_) {});
    }
    final tf = planJourneys(a, b);
    _transitFuture = tf;
    tf.then((p) {
      if (mounted && gen == _gen && p.isNotEmpty) setState(() => _modeSecs[RouteMode.transit] = p.first.seconds);
    }, onError: (_) {});
    await _applyMode();
  }

  Future<void> _applyMode() async {
    final a = _from ?? _me;
    final b = _to;
    if (a == null || b == null) return;
    final my = ++_applyN;
    final gen = _gen;
    bool stale() => !mounted || my != _applyN || gen != _gen;
    setState(() {
      _routing = true;
      _result = null;
      _plans = [];
      _planIdx = 0;
      _routeError = null;
      _estimate = false;
    });
    try {
      if (_mode == RouteMode.transit) {
        try {
          final plans = await (_transitFuture ??= planJourneys(a, b));
          if (stale()) return;
          _plans = plans;
        } catch (e) {
          final r = await _rf[RouteMode.car]!;
          if (stale()) return;
          _result = RouteResult(r.points, r.meters, r.meters / (22000 / 3600) + 900);
          _estimate = true;
          _routeError = '$e'.replaceFirst('Exception: ', '');
        }
      } else {
        final r = await _rf[_mode]!;
        if (stale()) return;
        _result = r;
      }
    } catch (e) {
      if (!stale()) _routeError = '$e'.replaceFirst('Exception: ', '');
    }
    if (!stale()) setState(() => _routing = false);
  }

  // ------------------------------------------------------------------ радар
  void _startRadarTimer() {
    _radarTimer?.cancel();
    _radarTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) {
      final r = _radar;
      if (!_radarPlaying || r == null || !mounted) return;
      setState(() => _radarIdx = (_radarIdx + 1) % r.frames.length);
    });
  }

  Future<void> _toggleRadar(bool v, void Function() refreshSheet) async {
    setState(() => _radarOn = v);
    refreshSheet();
    if (!v) {
      _radarTimer?.cancel();
      return;
    }
    try {
      if (_radar == null) {
        final r = await loadRadar();
        if (!mounted) return;
        setState(() {
          _radar = r;
          _radarIdx = r.currentIndex;
        });
      }
      _startRadarTimer();
    } catch (_) {
      _snack('Радар сейчас недоступен');
      if (mounted) setState(() => _radarOn = false);
      refreshSheet();
    }
  }

  String? get _radarUrl {
    final r = _radar;
    if (r == null) return null;
    return '${r.host}${r.frames[_radarIdx].path}/256/{z}/{x}/{y}/4/1_1.png';
  }

  String get _radarLabel {
    final r = _radar;
    if (r == null) return '';
    final f = r.frames[_radarIdx];
    final t = DateTime.fromMillisecondsSinceEpoch(f.time * 1000);
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return f.nowcast ? '$hh:$mm прогноз' : '$hh:$mm';
  }

  void _openLayers() {
    showModalBottomSheet(
      context: context,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(Config.pirate ? 'Выбери карту, капитан' : 'Вид карты', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in MapBase.values)
                ChoiceChip(
                  avatar: Icon(b.icon, size: 18),
                  label: Text(b.label),
                  selected: _base == b,
                  onSelected: (_) {
                    setState(() => _base = b);
                    Config.baseName = b.name;
                    Config.saveView();
                    setS(() {});
                    _fetch();
                  },
                )
            ]),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.grain, color: Color(0xFF1E88E5)),
              title: const Text('Радар осадков'),
              subtitle: const Text('Анимация за последние часы и прогноз на ближайшее время'),
              value: _radarOn,
              onChanged: (v) => _toggleRadar(v, () {
                if (ctx.mounted) setS(() {});
              }),
            ),
          ]),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ тайлы
  static const _clarity = 'https://clarity.maptiles.arcgis.com/arcgis/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

  /// Какие плитки нужны для выбранной подложки (используется и для подгрузки заранее).
  List<_Layer> _baseSpecs(MapBase b) => switch (b) {
        MapBase.scheme => [_Layer('$_esri/World_Street_Map/MapServer/tile/{z}/{y}/{x}')],
        MapBase.topo || MapBase.vintage => [_Layer('$_esri/World_Topo_Map/MapServer/tile/{z}/{y}/{x}')],
        MapBase.dark => [
            _Layer('$_esri/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}', 16),
            _Layer('$_esri/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}', 16),
          ],
        MapBase.osm => [_Layer('https://tile.openstreetmap.org/{z}/{x}/{y}.png')],
        // Clarity: самые свежие и чёткие снимки Esri; где их нет, берётся обычный World Imagery
        MapBase.satellite => [_Layer(_clarity, 19)],
        MapBase.hybrid => [
            _Layer(_clarity, 19),
            _Layer('$_esri/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}', 18),
            _Layer('$_esri/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}', 18),
          ],
      };

  /// Старинная карта: тёплая бумага, суша светлее моря, подписи тёмно-коричневыми чернилами.
  /// Названия остаются современными, меняются только краски.
  static const List<double> _vintageMatrix = <double>[
    1.135, -0.291, -0.059, 0, 49.5,
    0.397, 0.365, 0.053, 0, 30.5,
    0.288, -0.037, 0.515, 0, 13.3,
    0, 0, 0, 1, 0,
  ];

  /// Грузятся только видимые плитки плюс два ряда запаса вокруг: край экрана не мигает пустотой.
  /// Плитки появляются сразу, без плавного проявления.
  TileLayer _tile(_Layer l) => TileLayer(
        urlTemplate: l.url,
        userAgentPackageName: 'com.example.transit_map',
        maxNativeZoom: l.maxZoom,
        panBuffer: 2,
        keepBuffer: 4,
        tileDisplay: TileDisplay.instantaneous(),
        tileProvider: _tileProvider,
      );

  List<Widget> _tileLayers() {
    final layers = <Widget>[];
    for (final sp in _baseSpecs(_base)) {
      final t = _tile(sp);
      layers.add(_base == MapBase.vintage
          ? ColorFiltered(colorFilter: const ColorFilter.matrix(_vintageMatrix), child: t)
          : t);
    }
    final url = _radarUrl;
    if (_radarOn && url != null) {
      layers.add(Opacity(
        opacity: 0.75,
        child: TileLayer(
          urlTemplate: url,
          userAgentPackageName: 'com.example.transit_map',
          maxNativeZoom: 7,
        ),
      ));
    }
    return layers;
  }

  String get _attribution => switch (_base) {
        MapBase.osm => '© OpenStreetMap contributors',
        MapBase.satellite || MapBase.hybrid => 'Imagery © Esri (Clarity), Maxar, Earthstar Geographics',
        _ => 'Map © Esri, HERE, Garmin, © OpenStreetMap contributors',
      };

  // ---------------------------------------------------------------- экран
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pirate = Config.pirate;
    final vintage = _base == MapBase.vintage;

    final lines = <Polyline>[
      for (final l in _lineRoute)
        Polyline(
            points: l,
            strokeWidth: 6,
            color: const Color(0xFFE65100),
            borderStrokeWidth: 2,
            borderColor: Colors.white),
      if (_result != null)
        Polyline(
          points: _result!.points,
          strokeWidth: 6,
          color: _mode.color,
          borderStrokeWidth: 2,
          borderColor: Colors.white,
          pattern: _estimate ? StrokePattern.dashed(segments: const [10, 8]) : const StrokePattern.solid(),
        ),
      if (_plans.isNotEmpty)
        for (final l in _plans[_planIdx].legs)
          Polyline(
            points: l.points,
            strokeWidth: 6,
            color: legColor(l.mode),
            borderStrokeWidth: 2,
            borderColor: Colors.white,
            pattern: l.mode == 'WALK'
                ? StrokePattern.dashed(segments: const [8, 8])
                : const StrokePattern.solid(),
          ),
    ];

    Widget fab(String tag, String tip, IconData icon, Color color, VoidCallback onTap) =>
        FloatingActionButton.small(
          heroTag: tag,
          tooltip: tip,
          backgroundColor: pirate ? null : color,
          foregroundColor: pirate ? null : Colors.white,
          onPressed: onTap,
          child: Icon(icon),
        );

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: LatLng(Config.lastLat ?? 59.9343, Config.lastLon ?? 30.3351),
            initialZoom: Config.lastZoom.clamp(2.0, 19.0).toDouble(),
            minZoom: 2,
            maxZoom: 19,
            backgroundColor: vintage ? const Color(0xFFE2D3A6) : const Color(0xFFDDDDDD),
            onMapReady: () {
              _mapReady = true;
              Boot.set('Загружаю карту и остановки…');
              _fetch();
              Future<void>.delayed(const Duration(milliseconds: 2600), _bootReady);
              if (Config.autoLocate) unawaited(_locate(move: false, auto: true));
            },
            onPositionChanged: (cam, gesture) {
              // поворот карты отключён: значки на холсте рассчитаны на север сверху
              if (_mapReady && cam.rotation.abs() > 0.01) _map.rotate(0);
              _onMove(cam, gesture);
            },
            onTap: (_, p) {
              if (_found.isNotEmpty) setState(() => _found = []);
              if (_picking != 0) {
                final isFrom = _picking == 1;
                setState(() => _picking = 0);
                isFrom ? _setFrom(p, 'Точка на карте') : _setTo(p, 'Точка на карте');
                return;
              }
              final z = _map.camera.zoom;
              if (vintage && Config.seaLore) {
                final lore = loreAt(p, z);
                if (lore != null) {
                  _showLore(lore);
                  return;
                }
              }
              final st = stopAt(p, z, _kinds);
              if (st != null) {
                _openStop(st);
                return;
              }
              final dot = dotAt(p, z, _kinds);
              if (dot != null) {
                setState(() => _pin = dot.pos);
                _showInfo(dot.pos, hint: dot.name);
                return;
              }
              setState(() => _pin = p);
              _showInfo(p);
            },
            onSecondaryTap: (_, p) => _setTo(p, 'Точка на карте'),
          ),
          children: [
            ..._tileLayers(),
            if (vintage && Config.seaLore) SeaLoreLayer(label: pirateScript()),
            PolylineLayer(polylines: lines),
            StopsLayer(kinds: _kinds, repaint: _repaint, ink: pirate || vintage),
            if (_me != null && _meAcc > 0)
              CircleLayer(circles: [
                CircleMarker(
                  point: _me!,
                  radius: _meAcc.clamp(10.0, 20000.0).toDouble(),
                  useRadiusInMeter: true,
                  color: _meApprox ? const Color(0x182979FF) : const Color(0x222979FF),
                  borderColor: const Color(0x662979FF),
                  borderStrokeWidth: 1.5,
                )
              ]),
            MarkerLayer(markers: [
              if (_pin != null)
                Marker(
                    point: _pin!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on, color: pirate ? Pirate.wax : const Color(0xFFE53935), size: 40)),
              if (_me != null)
                Marker(
                  point: _me!,
                  width: 26,
                  height: 26,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF2979FF),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
                    ),
                  ),
                ),
              if (_from != null)
                Marker(point: _from!, child: const Icon(Icons.trip_origin, color: Colors.green, size: 30)),
              if (_to != null)
                Marker(
                    point: _to!,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.flag_circle, color: Colors.red, size: 40)),
            ]),
            // лицензионные указания источников данных скрыты за маленьким значком «i»
            RichAttributionWidget(
              showFlutterMapAttribution: false,
              attributions: [TextSourceAttribution(_attribution)],
            ),
          ],
        ),

        if (pirate || vintage) VintageOverlay(vignette: vintage, compass: vintage && !_routeOpen, paper: vintage),

        // кнопки справа
        Positioned(
          right: 22,
          top: 22,
          child: Column(children: [
            fab('layers', 'Вид карты и радар', pirate ? Icons.map : Icons.layers, const Color(0xFF7E57C2), _openLayers),
            const SizedBox(height: 8),
            fab('route', pirate ? 'Проложить курс' : 'Построить маршрут', pirate ? Icons.sailing : Icons.directions,
                const Color(0xFF1E6FD9), () => setState(() => _routeOpen = true)),
            const SizedBox(height: 8),
            fab('loc', 'Моё положение', pirate ? Icons.explore : Icons.my_location, const Color(0xFF2E9E5B), _locate),
            const SizedBox(height: 8),
            fab('set', 'Настройки', pirate ? Icons.anchor : Icons.settings, const Color(0xFFEF8A17), () async {
              await showSettings(context);
              if (!mounted) return;
              setState(() {});
              _refreshVisible();
            }),
          ]),
        ),

        // управление радаром
        if (_radarOn && _radar != null && _radar!.frames.length > 1)
          Positioned(
            right: 22,
            bottom: 50,
            child: SizedBox(
              width: 360,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(children: [
                    IconButton(
                      tooltip: _radarPlaying ? 'Пауза' : 'Воспроизвести',
                      onPressed: () => setState(() => _radarPlaying = !_radarPlaying),
                      icon: Icon(_radarPlaying ? Icons.pause_circle : Icons.play_circle,
                          color: const Color(0xFF1E88E5), size: 30),
                    ),
                    Expanded(
                      child: Slider(
                        value: _radarIdx.toDouble(),
                        min: 0,
                        max: (_radar!.frames.length - 1).toDouble(),
                        divisions: _radar!.frames.length - 1,
                        onChanged: (v) => setState(() {
                          _radarIdx = v.round();
                          _radarPlaying = false;
                        }),
                      ),
                    ),
                    SizedBox(
                        width: 92,
                        child: Text(_radarLabel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  ]),
                ),
              ),
            ),
          ),

        // поиск, фильтры и подсказки
        Positioned.fill(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 80, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(pirate ? 10 : 28),
                      side: pirate ? const BorderSide(color: Pirate.brown, width: 2) : BorderSide.none,
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (q) => _search(q),
                      decoration: InputDecoration(
                        hintText: pirate ? 'Куда держим курс, капитан?' : 'Поиск города, адреса, места',
                        prefixIcon: Icon(Icons.search, color: cs.primary),
                        suffixIcon: (_searching || _loading)
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                            : IconButton(
                                tooltip: 'Найти',
                                onPressed: () => _search(_searchCtrl.text),
                                icon: const Icon(Icons.arrow_forward)),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  if (_found.isNotEmpty)
                    Card(
                      child: Column(children: [
                        for (final p in _found)
                          ListTile(
                            dense: true,
                            leading: Icon(Icons.place, color: cs.tertiary),
                            title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: p.subtitle.isEmpty
                                ? null
                                : Text(p.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _openFound(p),
                          )
                      ]),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 38,
                    child: ListView(scrollDirection: Axis.horizontal, children: [
                      for (final k in StopKind.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: FilterChip(
                            avatar: Icon(k.icon, size: 16, color: k.color),
                            label: Text(k.label),
                            selected: _kinds.contains(k),
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _kinds.add(k);
                                } else {
                                  _kinds.remove(k);
                                }
                              });
                              _refreshVisible();
                            },
                          ),
                        ),
                    ]),
                  ),
                  if (_hint != null && _found.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Chip(label: Text(_hint!), visualDensity: VisualDensity.compact),
                    ),
                  if (_lineLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Chip(
                        avatar: const Icon(Icons.route, size: 18, color: Color(0xFFE65100)),
                        label: Text(_lineLabel!, overflow: TextOverflow.ellipsis),
                        onDeleted: () => setState(() {
                          _lineRoute = [];
                          _lineLabel = null;
                        }),
                      ),
                    ),
                  if (_picking != 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Chip(
                        avatar: const Icon(Icons.touch_app, size: 18),
                        label: Text(_picking == 1 ? 'Нажмите на карту: откуда ехать' : 'Нажмите на карту: куда ехать'),
                        onDeleted: () => setState(() => _picking = 0),
                      ),
                    ),
                ]),
              ),
            ),
          ),
        ),

        // панель маршрута
        if (_routeOpen)
          Positioned.fill(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470, maxHeight: 480),
                  child: _routePanel(cs),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  // ----------------------------------------------------------- панель маршрута
  Widget _pointRow(IconData icon, Color color, String text, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
      );

  Widget _modeTabs() => Row(children: [
        for (final m in RouteMode.values)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  setState(() => _mode = m);
                  _applyMode();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _mode == m ? m.color.withAlpha(40) : null,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _mode == m ? m.color : Colors.transparent, width: 1.5),
                  ),
                  child: Column(children: [
                    Icon(m.icon, color: m.color),
                    const SizedBox(height: 2),
                    Text(
                      _modeSecs[m] != null ? fmtDuration(_modeSecs[m]!) : (_to == null ? '' : '…'),
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]);

  Widget _routePanel(ColorScheme cs) {
    final fromText = _from != null ? _fromName : (_me != null ? 'Моё положение' : 'Откуда: нажмите и выберите точку');
    final toText = _to != null ? _toName : 'Куда: нажмите и выберите точку';
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(Config.pirate ? 'Проложить курс' : 'Маршрут', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            IconButton(tooltip: 'Закрыть', onPressed: _closeRoute, icon: const Icon(Icons.close)),
          ]),
          Row(children: [
            Expanded(
              child: Column(children: [
                _pointRow(Icons.trip_origin, Colors.green, fromText, () => _editPoint(true)),
                _pointRow(Icons.flag_circle, Colors.red, toText, () => _editPoint(false)),
              ]),
            ),
            IconButton(tooltip: 'Поменять местами', onPressed: _swap, icon: const Icon(Icons.swap_vert)),
          ]),
          const SizedBox(height: 6),
          _modeTabs(),
          const SizedBox(height: 10),
          if (_routing) const LinearProgressIndicator(),
          if (_routeError != null) Text(_routeError!, style: TextStyle(color: cs.error)),
          if (_result != null) ...[
            const SizedBox(height: 6),
            Text('${_estimate ? "≈ " : ""}${fmtDuration(_result!.seconds)} · ${fmtDistance(_result!.meters)}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: _mode.color)),
            if (_estimate)
              Text('Оценка по средней скорости транспорта, не по расписанию.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
          if (_plans.isNotEmpty) ..._planWidgets(cs),
        ]),
      ),
    );
  }

  List<Widget> _planWidgets(ColorScheme cs) {
    final p = _plans[_planIdx];
    final osm = p.source == 'OpenStreetMap';
    return [
      Wrap(spacing: 8, runSpacing: 4, children: [
        for (var i = 0; i < _plans.length; i++)
          ChoiceChip(
            label: Text('${fmtDuration(_plans[i].seconds)} · '
                '${_plans[i].transfers == 0 ? "без пересадок" : "пересадок: ${_plans[i].transfers}"}'),
            selected: i == _planIdx,
            onSelected: (_) => setState(() => _planIdx = i),
          ),
      ]),
      const SizedBox(height: 12),
      for (var i = 0; i < p.legs.length; i++) _legTile(p.legs, i, cs),
      Text(
        osm
            ? 'Маршрут построен по данным OpenStreetMap без реального расписания: время приблизительное. '
                'Для точного времени добавьте ключи HERE или 2ГИС в настройках.'
            : 'Данные: ${p.source}',
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      ),
    ];
  }

  Widget _legTile(List<TransitLeg> legs, int i, ColorScheme cs) {
    final l = legs[i];
    final isWalk = l.mode == 'WALK';
    final minutes = (l.seconds / 60).round();
    final last = i == legs.length - 1;
    String title;
    var sub = '';
    if (isWalk) {
      if (i == 0) {
        title = l.to.isNotEmpty ? 'Пешком $minutes мин до остановки «${l.to}»' : 'Пешком $minutes мин';
      } else if (last) {
        title = 'Пешком $minutes мин до точки назначения';
      } else {
        title = 'Пересадка: пройдите $minutes мин${l.to.isNotEmpty ? " до остановки «${l.to}»" : ""}';
      }
    } else {
      final prevRide = i > 0 && legs[i - 1].mode != 'WALK';
      title = '${prevRide ? "Пересадка · " : ""}${legModeRu(l.mode)} ${l.route}'.trim();
      final parts = <String>[
        if (l.stops > 0) '${l.stops} ост.',
        '≈ $minutes мин в пути',
        if (l.waitSeconds > 0) 'ожидание ≈ ${(l.waitSeconds / 60).round()} мин',
      ];
      sub = 'Сядьте на «${l.from}», выйдите на «${l.to}»\n${parts.join(' · ')}';
    }
    final color = legColor(l.mode);
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 30,
          child: Column(children: [
            CircleAvatar(radius: 14, backgroundColor: color, child: Icon(legIcon(l.mode), size: 16, color: Colors.white)),
            if (!last) Expanded(child: Center(child: Container(width: 3, color: color.withAlpha(110)))),
          ]),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (sub.isNotEmpty) Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ]),
          ),
        ),
      ]),
    );
  }
}
