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

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _map = MapController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  // карта
  MapBase _base = MapBase.scheme;
  bool _radarOn = false;
  String? _radarUrl;
  List<Stop> _stops = [];
  List<PlaceDot> _dots = [];
  bool _loading = false;
  String? _hint;

  // поиск
  List<Place> _found = [];
  bool _searching = false;

  // точки и маршрут
  LatLng? _me, _from, _to, _pin;
  String _fromName = '', _toName = '';
  int _picking = 0; // 0 нет, 1 выбираем «откуда», 2 выбираем «куда»
  bool _routeOpen = false;
  RouteMode _mode = RouteMode.walk;
  RouteResult? _result;
  bool _estimate = false;
  List<TransitPlan> _plans = [];
  int _planIdx = 0;
  String? _routeError;
  bool _routing = false;

  // линия выбранного маршрута транспорта
  List<List<LatLng>> _lineRoute = [];
  String? _lineLabel;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  // ------------------------------------------------ загрузка объектов карты
  void _onMove(MapCamera cam) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () => _refresh(cam));
  }

  Future<void> _refresh(MapCamera cam) async {
    final z = cam.zoom;
    if (z < 8) {
      setState(() {
        _stops = [];
        _dots = [];
        _hint = 'Приблизьте карту, чтобы увидеть города и остановки';
      });
      return;
    }
    setState(() => _loading = true);
    try {
      if (z >= Config.minStopsZoom) {
        final s = await loadStops(cam.visibleBounds);
        if (!mounted) return;
        setState(() {
          _stops = s;
          _dots = [];
          _hint = s.isEmpty ? 'В этой области остановок в OpenStreetMap нет' : null;
        });
      } else {
        final d = await loadPlaceDots(cam.visibleBounds, z);
        if (!mounted) return;
        setState(() {
          _dots = d;
          _stops = [];
          _hint = 'Приблизьте карту, чтобы увидеть остановки';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _hint = 'Не удалось загрузить данные, попробуйте ещё раз');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ------------------------------------------------------------------ поиск
  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _searching = true);
    try {
      final r = await searchPlaces(q.trim(), _map.camera.center);
      if (!mounted) return;
      setState(() => _found = r);
      if (r.isEmpty) _snack('Ничего не найдено');
    } catch (e) {
      _snack('Поиск не удался, проверьте интернет');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _openFound(Place p) {
    _map.move(p.pos, 15);
    setState(() {
      _found = [];
      _pin = p.pos;
    });
    _showInfo(p.pos);
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
  void _showInfo(LatLng p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 520),
      builder: (_) => InfoSheet(
        pos: p,
        zoom: _map.camera.zoom,
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

  void _closeRoute() => setState(() {
        _routeOpen = false;
        _from = _to = null;
        _result = null;
        _plans = [];
        _routeError = null;
        _estimate = false;
      });

  Future<void> _buildRoute() async {
    final a = _from ?? _me;
    final b = _to;
    setState(() {
      _result = null;
      _plans = [];
      _planIdx = 0;
      _routeError = null;
      _estimate = false;
    });
    if (a == null || b == null) return;
    setState(() => _routing = true);
    try {
      if (_mode == RouteMode.transit) {
        if (Config.otpUrl.isNotEmpty) {
          _plans = await buildTransitPlans(a, b);
        } else {
          // Нет сервера расписаний: оценка по средней скорости городского транспорта.
          final r = await buildRoute(a, b, RouteMode.car);
          _result = RouteResult(r.points, r.meters, r.meters / (22000 / 3600) + 900);
          _estimate = true;
        }
      } else {
        _result = await buildRoute(a, b, _mode);
      }
    } catch (e) {
      _routeError = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _routing = false);
  }

  // -------------------------------------------------------- слои и настройки
  Future<void> _toggleRadar(bool v, void Function() refreshSheet) async {
    setState(() => _radarOn = v);
    refreshSheet();
    if (v && _radarUrl == null) {
      try {
        final u = await loadRadarTemplate();
        if (mounted) setState(() => _radarUrl = u);
      } catch (_) {
        _snack('Радар сейчас недоступен');
        if (mounted) setState(() => _radarOn = false);
        refreshSheet();
      }
    }
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
              title: const Text('Радар осадков'),
              subtitle: const Text('Погодный радар поверх карты'),
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
  TileLayer _tile(String url,
          {List<String> sub = const ['a', 'b', 'c'], int maxZoom = 19}) =>
      TileLayer(
        urlTemplate: url,
        subdomains: sub,
        userAgentPackageName: 'com.example.transit_map',
        maxNativeZoom: maxZoom,
      );

  List<Widget> _tileLayers() {
    const carto = ['a', 'b', 'c', 'd'];
    const esri =
        'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
    final layers = <Widget>[
      switch (_base) {
        MapBase.scheme => _tile(
            'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
            sub: carto),
        MapBase.dark => _tile(
            'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
            sub: carto),
        MapBase.osm => _tile('https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
        MapBase.satellite || MapBase.hybrid => _tile(esri, maxZoom: 18),
      },
      if (_base == MapBase.hybrid)
        _tile('https://{s}.basemaps.cartocdn.com/dark_only_labels/{z}/{x}/{y}.png', sub: carto),
      if (_radarOn && _radarUrl != null)
        Opacity(
          opacity: 0.7,
          child: TileLayer(
            urlTemplate: _radarUrl!,
            userAgentPackageName: 'com.example.transit_map',
            maxNativeZoom: 7,
          ),
        ),
    ];
    return layers;
  }

  String get _attribution => switch (_base) {
        MapBase.scheme || MapBase.dark => '© OpenStreetMap contributors, © CARTO',
        MapBase.osm => '© OpenStreetMap contributors',
        MapBase.satellite => 'Imagery © Esri, Maxar, Earthstar Geographics',
        MapBase.hybrid => 'Imagery © Esri, Maxar; labels © CARTO, OpenStreetMap contributors',
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
          onTap: () => _showInfo(d.pos),
          child: Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = <Polyline>[
      for (final l in _lineRoute)
        Polyline(points: l, strokeWidth: 6, color: const Color(0xFFE65100)),
      if (_result != null)
        Polyline(
          points: _result!.points,
          strokeWidth: 5,
          color: cs.primary,
          pattern: _estimate
              ? StrokePattern.dashed(segments: const [10, 8])
              : const StrokePattern.solid(),
        ),
      if (_plans.isNotEmpty)
        for (final l in _plans[_planIdx].legs)
          Polyline(
            points: l.points,
            strokeWidth: 5,
            color: l.mode == 'WALK' ? Colors.grey : cs.primary,
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
              for (final s in _stops)
                Marker(
                  point: s.pos,
                  width: 34,
                  height: 34,
                  child: Tooltip(
                    message: s.name,
                    child: GestureDetector(
                      onTap: () => _openStop(s),
                      child: Container(
                        decoration: BoxDecoration(
                          color: s.kind.color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: const [BoxShadow(blurRadius: 3, color: Colors.black38)],
                        ),
                        child: Icon(s.kind.icon, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ),
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
            RichAttributionWidget(attributions: [TextSourceAttribution(_attribution)]),
          ],
        ),

        // кнопки справа
        Positioned(
          right: 12,
          top: 12,
          child: Column(children: [
            FloatingActionButton.small(
                heroTag: 'layers', tooltip: 'Вид карты', onPressed: _openLayers, child: const Icon(Icons.layers)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
                heroTag: 'route',
                tooltip: 'Построить маршрут',
                onPressed: () => setState(() => _routeOpen = true),
                child: const Icon(Icons.directions)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
                heroTag: 'loc', tooltip: 'Моё положение', onPressed: _locate, child: const Icon(Icons.my_location)),
            const SizedBox(height: 8),
            FloatingActionButton.small(
                heroTag: 'set',
                tooltip: 'Настройки',
                onPressed: () => showSettings(context),
                child: const Icon(Icons.settings)),
          ]),
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
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _search,
                      decoration: InputDecoration(
                        hintText: 'Поиск города, адреса, места',
                        prefixIcon: const Icon(Icons.search),
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
                            leading: const Icon(Icons.place_outlined),
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
                        avatar: const Icon(Icons.route, size: 18),
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
                  constraints: const BoxConstraints(maxWidth: 460, maxHeight: 380),
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
                avatar: Icon(m.icon, size: 18),
                label: Text(m.label),
                selected: _mode == m,
                onSelected: (_) {
                  setState(() => _mode = m);
                  _buildRoute();
                },
              )
          ]),
          const SizedBox(height: 10),
          if (_routing) const LinearProgressIndicator(),
          if (_routeError != null) Text(_routeError!, style: TextStyle(color: cs.error)),
          if (_result != null) ...[
            Text('${_estimate ? "≈ " : ""}${fmtDuration(_result!.seconds)} · ${fmtDistance(_result!.meters)}',
                style: Theme.of(context).textTheme.titleLarge),
            if (_estimate)
              Text(
                  'Оценка по средней скорости транспорта и времени ожидания, не по расписанию. '
                  'Для точных маршрутов укажите сервер OpenTripPlanner в настройках.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
          if (_plans.isNotEmpty) ..._planWidgets(),
        ]),
      ),
    );
  }

  List<Widget> _planWidgets() {
    final p = _plans[_planIdx];
    return [
      Wrap(spacing: 8, children: [
        for (var i = 0; i < _plans.length; i++)
          ChoiceChip(
            label: Text(fmtDuration(_plans[i].seconds)),
            selected: i == _planIdx,
            onSelected: (_) => setState(() => _planIdx = i),
          ),
      ]),
      const SizedBox(height: 6),
      for (final l in p.legs)
        Text(l.mode == 'WALK'
            ? 'Пешком ${fmtDuration(l.seconds)}'
            : '${l.mode} ${l.route}: ${l.from} → ${l.to} (${fmtDuration(l.seconds)})'),
    ];
  }
}
