import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'config.dart';
import 'info_sheet.dart';
import 'models.dart';
import 'place_picker.dart';
import 'services.dart';
import 'settings_dialog.dart';
import 'stop_sheet.dart';
import 'transit_planner.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _esri = 'https://server.arcgisonline.com/ArcGIS/rest/services';

  final _map = MapController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce, _searchDebounce, _radarTimer;

  // карта
  MapBase _base = MapBase.scheme;
  List<Stop> _stops = [];
  List<PlaceDot> _dots = [];
  bool _loading = false;
  String? _hint;
  LatLngBounds? _loadedBounds;
  String _loadedKind = '';

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
  int _routeToken = 0;
  Map<RouteMode, Future<RouteResult>> _rf = {};
  Future<List<TransitPlan>>? _transitFuture;

  // линия выбранного маршрута транспорта
  List<List<LatLng>> _lineRoute = [];
  String? _lineLabel;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    _radarTimer?.cancel();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  // ------------------------------------------------ загрузка объектов карты
  void _onMove(MapCamera cam) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _refresh(cam));
  }

  Future<void> _refresh(MapCamera cam) async {
    final z = cam.zoom;
    if (z < 8) {
      _loadedBounds = null;
      _loadedKind = '';
      setState(() {
        _stops = [];
        _dots = [];
        _hint = 'Приблизьте карту, чтобы увидеть города и остановки';
      });
      return;
    }
    final kind = z >= Config.minStopsZoom ? 'stops' : 'dots${z < 10 ? 1 : (z < 12 ? 2 : 3)}';
    final vb = cam.visibleBounds;
    // если область уже загружена, повторный запрос не нужен
    if (_loadedKind == kind && _loadedBounds != null && _loadedBounds!.containsBounds(vb)) {
      return;
    }
    final dh = (vb.north - vb.south) * 0.3;
    final dw = (vb.east - vb.west) * 0.3;
    final big = LatLngBounds(
      LatLng((vb.south - dh).clamp(-85.0, 85.0), (vb.west - dw).clamp(-180.0, 180.0)),
      LatLng((vb.north + dh).clamp(-85.0, 85.0), (vb.east + dw).clamp(-180.0, 180.0)),
    );
    setState(() => _loading = true);
    try {
      if (kind == 'stops') {
        final s = await loadStops(big);
        if (!mounted) return;
        setState(() {
          _stops = s;
          _dots = [];
          _hint = s.isEmpty ? 'В этой области остановок в OpenStreetMap нет' : null;
        });
      } else {
        final d = await loadPlaceDots(big, z);
        if (!mounted) return;
        setState(() {
          _dots = d;
          _stops = [];
          _hint = 'Приблизьте карту, чтобы увидеть остановки';
        });
      }
      _loadedBounds = big;
      _loadedKind = kind;
    } catch (e) {
      if (mounted) setState(() => _hint = 'Не удалось загрузить данные, попробуйте ещё раз');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------------ поиск
  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _found = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 350), () => _search(q, auto: true));
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
    } catch (e) {
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

  Future<void> _locate({bool move = true}) async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _snack('Нет доступа к геолокации');
        return;
      }
      final p = await Geolocator.getCurrentPosition();
      final ll = LatLng(p.latitude, p.longitude);
      setState(() => _me = ll);
      if (move) _map.move(ll, 16);
    } catch (_) {
      _snack('Не удалось определить положение');
    }
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
      _map.fitCamera(CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts), padding: const EdgeInsets.all(70)));
    } catch (e) {
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
    _routeToken++;
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
    });
  }

  /// Запускает расчёт сразу для пешком / авто / велосипеда,
  /// поэтому переключение режимов потом происходит мгновенно.
  Future<void> _buildRoute() async {
    final a = _from ?? _me;
    final b = _to;
    final token = ++_routeToken;
    setState(() {
      _result = null;
      _plans = [];
      _planIdx = 0;
      _routeError = null;
      _estimate = false;
      _routing = false;
      _rf = {};
      _transitFuture = null;
    });
    if (a == null || b == null) return;
    _rf = {
      for (final m in [RouteMode.walk, RouteMode.car, RouteMode.bike]) m: buildRoute(a, b, m)
    };
    for (final f in _rf.values) {
      f.ignore();
    }
    await _applyMode(token);
  }

  Future<void> _applyMode(int token) async {
    final a = _from ?? _me;
    final b = _to;
    if (a == null || b == null) return;
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
          final plans = Config.otpUrl.isNotEmpty
              ? await buildTransitPlans(a, b)
              : await (_transitFuture ??= planTransit(a, b));
          if (token != _routeToken) return;
          _plans = plans;
        } catch (e) {
          // запасной вариант: оценка по средней скорости
          final r = await _rf[RouteMode.car]!;
          if (token != _routeToken) return;
          _result = RouteResult(r.points, r.meters, r.meters / (22000 / 3600) + 900);
          _estimate = true;
          _routeError = '$e'.replaceFirst('Exception: ', '');
        }
      } else {
        final r = await _rf[_mode]!;
        if (token != _routeToken) return;
        _result = r;
      }
    } catch (e) {
      if (token == _routeToken) _routeError = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted && token == _routeToken) setState(() => _routing = false);
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
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: const EdgeInsets.all(18),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Вид карты', style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final b in MapBase.values)
                ChoiceChip(
                  avatar: Icon(b.icon, size: 18),
                  label: Text(b.label),
                  selected: _base == b,
                  onSelected: (_) {
                    setState(() => _base = b);
                    setS(() {});
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
  TileLayer _tile(String url, {int maxZoom = 19}) => TileLayer(
        urlTemplate: url,
        userAgentPackageName: 'com.example.transit_map',
        maxNativeZoom: maxZoom,
      );

  List<Widget> _tileLayers() {
    final layers = <Widget>[];
    switch (_base) {
      case MapBase.scheme:
        layers.add(_tile('$_esri/World_Street_Map/MapServer/tile/{z}/{y}/{x}'));
      case MapBase.topo:
        layers.add(_tile('$_esri/World_Topo_Map/MapServer/tile/{z}/{y}/{x}'));
      case MapBase.dark:
        layers.add(_tile('$_esri/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}', maxZoom: 16));
        layers.add(_tile('$_esri/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}', maxZoom: 16));
      case MapBase.osm:
        layers.add(_tile('https://tile.openstreetmap.org/{z}/{x}/{y}.png'));
      case MapBase.satellite:
        layers.add(_tile('$_esri/World_Imagery/MapServer/tile/{z}/{y}/{x}', maxZoom: 18));
      case MapBase.hybrid:
        layers.add(_tile('$_esri/World_Imagery/MapServer/tile/{z}/{y}/{x}', maxZoom: 18));
        layers.add(_tile('$_esri/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}', maxZoom: 18));
        layers.add(_tile('$_esri/Reference/World_Transportation/MapServer/tile/{z}/{y}/{x}', maxZoom: 18));
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
        MapBase.satellite || MapBase.hybrid => 'Imagery © Esri, Maxar, Earthstar Geographics',
        _ => 'Map © Esri, HERE, Garmin, © OpenStreetMap contributors',
      };

  // ---------------------------------------------------------------- маркеры
  Marker _dotMarker(PlaceDot d) {
    final size = switch (d.kind) {
      'city' => 18.0,
      'town' => 14.0,
      'village' => 11.0,
      _ => 9.0,
    };
    final color = switch (d.kind) {
      'city' => const Color(0xFFD32F2F),
      'town' => const Color(0xFFF57C00),
      'village' => const Color(0xFF388E3C),
      _ => const Color(0xFF757575),
    };
    return Marker(
      point: d.pos,
      width: 28,
      height: 28,
      child: Tooltip(
        message: d.population != null ? '${d.name} · ${d.population} чел.' : d.name,
        child: GestureDetector(
          onTap: () => _showInfo(d.pos, hint: d.name),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Marker _stopMarker(Stop s) => Marker(
        point: s.pos,
        width: 32,
        height: 32,
        child: GestureDetector(
          onTap: () => _openStop(s),
          child: Container(
            decoration: BoxDecoration(
              color: s.kind.color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(s.kind.icon, size: 17, color: Colors.white),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
          pattern: _estimate
              ? StrokePattern.dashed(segments: const [10, 8])
              : const StrokePattern.solid(),
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

    return Scaffold(
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: const LatLng(59.9343, 30.3351),
            initialZoom: 12,
            minZoom: 2,
            maxZoom: 19,
            onMapReady: () => _refresh(_map.camera),
            onPositionChanged: (cam, _) => _onMove(cam),
            onTap: (_, p) {
              if (_found.isNotEmpty) setState(() => _found = []);
              if (_picking != 0) {
                final isFrom = _picking == 1;
                setState(() => _picking = 0);
                isFrom ? _setFrom(p, 'Точка на карте') : _setTo(p, 'Точка на карте');
                return;
              }
              setState(() => _pin = p);
              _showInfo(p);
            },
            onSecondaryTap: (_, p) => _setTo(p, 'Точка на карте'),
          ),
          children: [
            ..._tileLayers(),
            PolylineLayer(polylines: lines),
            MarkerLayer(markers: [
              for (final d in _dots) _dotMarker(d),
              for (final s in _stops) _stopMarker(s),
              if (_pin != null)
                Marker(
                    point: _pin!,
                    width: 40,
                    height: 40,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: Color(0xFFE53935), size: 40)),
              if (_me != null)
                Marker(point: _me!, child: const Icon(Icons.my_location, color: Colors.blue, size: 28)),
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

        // кнопки справа
        Positioned(
          right: 12,
          top: 12,
          child: Column(children: [
            FloatingActionButton.small(
                heroTag: 'layers',
                tooltip: 'Вид карты и радар',
                backgroundColor: const Color(0xFF7E57C2),
                foregroundColor: Colors.white,
                onPressed: _openLayers,
                child: const Icon(Icons.layers)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
                heroTag: 'route',
                tooltip: 'Построить маршрут',
                backgroundColor: const Color(0xFF1E6FD9),
                foregroundColor: Colors.white,
                onPressed: () => setState(() => _routeOpen = true),
                child: const Icon(Icons.directions)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
                heroTag: 'loc',
                tooltip: 'Моё положение',
                backgroundColor: const Color(0xFF2E9E5B),
                foregroundColor: Colors.white,
                onPressed: _locate,
                child: const Icon(Icons.my_location)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
                heroTag: 'set',
                tooltip: 'Настройки',
                backgroundColor: const Color(0xFFEF8A17),
                foregroundColor: Colors.white,
                onPressed: () => showSettings(context),
                child: const Icon(Icons.settings)),
          ]),
        ),

        // управление радаром
        if (_radarOn && _radar != null && _radar!.frames.length > 1)
          Positioned(
            right: 12,
            bottom: 46,
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
                        child: Text(_radarLabel,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  ]),
                ),
              ),
            ),
          ),

        // поиск и подсказки
        Positioned.fill(
          child: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 70, 0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      onChanged: _onSearchChanged,
                      onSubmitted: (q) => _search(q),
                      decoration: InputDecoration(
                        hintText: 'Поиск города, адреса, места',
                        prefixIcon: Icon(Icons.search, color: cs.primary),
                        suffixIcon: (_searching || _loading)
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
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
                  if (_hint != null && _found.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Chip(label: Text(_hint!), visualDensity: VisualDensity.compact),
                    ),
                  if (_lineLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
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
                      padding: const EdgeInsets.only(top: 8),
                      child: Chip(
                        avatar: const Icon(Icons.touch_app, size: 18),
                        label: Text(_picking == 1
                            ? 'Нажмите на карту: откуда ехать'
                            : 'Нажмите на карту: куда ехать'),
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
                padding: const EdgeInsets.all(12),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470, maxHeight: 460),
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

  Widget _routePanel(ColorScheme cs) {
    final fromText = _from != null
        ? _fromName
        : (_me != null ? 'Моё положение' : 'Откуда: нажмите и выберите точку');
    final toText = _to != null ? _toName : 'Куда: нажмите и выберите точку';
    return Card(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('Маршрут', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
          Wrap(spacing: 8, children: [
            for (final m in RouteMode.values)
              ChoiceChip(
                avatar: Icon(m.icon, size: 18, color: m.color),
                label: Text(m.label),
                selectedColor: m.color.withAlpha(50),
                selected: _mode == m,
                onSelected: (_) {
                  setState(() => _mode = m);
                  _applyMode(++_routeToken);
                },
              )
          ]),
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
      const SizedBox(height: 10),
      for (var i = 0; i < p.legs.length; i++) _legTile(p.legs, i, cs),
      if (p.estimated)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              'Маршрут построен по данным OpenStreetMap без реального расписания: '
              'время приблизительное. Для точного времени укажите OpenTripPlanner в настройках.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
    ];
  }

  Widget _legTile(List<TransitLeg> legs, int i, ColorScheme cs) {
    final l = legs[i];
    final isWalk = l.mode == 'WALK';
    final minutes = (l.seconds / 60).round();
    String title;
    var sub = '';
    if (isWalk) {
      if (i == 0) {
        title = 'Пешком $minutes мин до остановки «${l.to}»';
      } else if (i == legs.length - 1) {
        title = 'Пешком $minutes мин до точки назначения';
      } else {
        title = 'Пересадка: пройдите $minutes мин до остановки «${l.to}»';
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: legColor(l.mode),
          child: Icon(legIcon(l.mode), size: 16, color: Colors.white),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (sub.isNotEmpty) Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}
