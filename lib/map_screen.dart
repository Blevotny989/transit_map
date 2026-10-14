import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'config.dart';
import 'models.dart';
import 'services.dart';
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

  List<Stop> _stops = [];
  List<Place> _found = [];
  bool _loading = false;
  String? _hint;

  LatLng? _me, _from, _to;
  String _fromName = '', _toName = '';
  RouteMode _mode = RouteMode.walk;
  RouteResult? _result;
  List<TransitPlan> _plans = [];
  int _planIdx = 0;
  String? _routeError;
  bool _routing = false;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // ---------- Остановки ----------
  void _onMove(MapCamera cam) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () => _refreshStops(cam));
  }

  Future<void> _refreshStops(MapCamera cam) async {
    if (cam.zoom < Config.minStopsZoom) {
      setState(() {
        _stops = [];
        _hint = 'Приблизьте карту, чтобы увидеть остановки';
      });
      return;
    }
    setState(() {
      _loading = true;
      _hint = null;
    });
    try {
      final s = await loadStops(cam.visibleBounds);
      if (mounted) setState(() => _stops = s);
    } catch (_) {
      if (mounted) setState(() => _hint = 'Не удалось загрузить остановки');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------- Поиск ----------
  Future<void> _search(String q) async {
    if (q.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    try {
      final r = await searchPlaces(q);
      setState(() => _found = r);
    } catch (_) {
      _snack('Поиск не удался');
    }
  }

  void _goTo(LatLng p, {double zoom = 16}) {
    _map.move(p, zoom);
    setState(() => _found = []);
  }

  Future<void> _locate() async {
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      _snack('Нет доступа к геолокации');
      return;
    }
    final p = await Geolocator.getCurrentPosition();
    final ll = LatLng(p.latitude, p.longitude);
    setState(() => _me = ll);
    _map.move(ll, 16);
  }

  // ---------- Маршрут ----------
  void _setFrom(LatLng p, String name) {
    setState(() {
      _from = p;
      _fromName = name;
    });
    _buildRoute();
  }

  void _setTo(LatLng p, String name) {
    setState(() {
      _to = p;
      _toName = name;
    });
    _buildRoute();
  }

  void _clearRoute() => setState(() {
        _from = _to = null;
        _result = null;
        _plans = [];
        _routeError = null;
      });

  Future<void> _buildRoute() async {
    final a = _from ?? _me;
    final b = _to;
    if (a == null || b == null) return;
    setState(() {
      _routing = true;
      _routeError = null;
      _result = null;
      _plans = [];
      _planIdx = 0;
    });
    try {
      if (_mode == RouteMode.transit) {
        _plans = await buildTransitPlans(a, b);
      } else {
        _result = await buildRoute(a, b, _mode);
      }
    } catch (e) {
      _routeError = '$e'.replaceFirst('Exception: ', '');
    }
    if (mounted) setState(() => _routing = false);
  }

  void _snack(String t) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  void _openStop(Stop s) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
      ),
    );
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final top = MediaQuery.of(context).padding.top;
    final lines = <Polyline>[
      if (_result != null)
        Polyline(points: _result!.points, strokeWidth: 5, color: cs.primary),
      if (_plans.isNotEmpty)
        for (final l in _plans[_planIdx].legs)
          Polyline(
            points: l.points,
            strokeWidth: 5,
            color: l.mode == 'WALK' ? Colors.grey : cs.primary,
            pattern: l.mode == 'WALK' ? StrokePattern.dashed(segments: const [8, 8]) : const StrokePattern.solid(),
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
            onMapReady: () => _refreshStops(_map.camera),
            onPositionChanged: (cam, _) => _onMove(cam),
            onLongPress: (_, p) => _setTo(p, 'Выбранная точка'),
            onSecondaryTap: (_, p) => _setTo(p, 'Выбранная точка'),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.transit_map',
            ),
            PolylineLayer(polylines: lines),
            MarkerLayer(markers: [
              for (final s in _stops)
                Marker(
                  point: s.pos,
                  width: 34,
                  height: 34,
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
              if (_me != null)
                Marker(
                    point: _me!,
                    child: const Icon(Icons.my_location, color: Colors.blue, size: 28)),
              if (_from != null)
                Marker(
                    point: _from!,
                    child: const Icon(Icons.trip_origin, color: Colors.green, size: 30)),
              if (_to != null)
                Marker(
                    point: _to!,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_on, color: Colors.red, size: 40)),
            ]),
            const RichAttributionWidget(attributions: [
              TextSourceAttribution('© OpenStreetMap contributors'),
            ]),
          ],
        ),

        // Поиск
        Positioned(
          top: top + 10,
          left: 12,
          right: 12,
          child: Column(children: [
            Card(
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Поиск места или адреса',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : null,
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
                      title: Text(p.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () {
                        _goTo(p.pos);
                        _setTo(p.pos, p.name.split(',').first);
                      },
                    )
                ]),
              ),
            if (_hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Chip(label: Text(_hint!), visualDensity: VisualDensity.compact),
              ),
          ]),
        ),

        // Кнопка геолокации
        Positioned(
          right: 12,
          bottom: (_to != null ? 250 : 24),
          child: FloatingActionButton(
              heroTag: 'loc', onPressed: _locate, child: const Icon(Icons.my_location)),
        ),

        if (_to != null) Positioned(left: 12, right: 12, bottom: 12, child: _routePanel(cs)),
      ]),
    );
  }

  Widget _routePanel(ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(
                '${_from == null ? "Моё положение" : _fromName}  →  $_toName',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(onPressed: _clearRoute, icon: const Icon(Icons.close)),
          ]),
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
          if (_from == null && _me == null && _routeError == null && !_routing)
            const Text('Включите геолокацию (кнопка справа) или выберите точку «Отсюда».'),
          if (_result != null)
            Text('${fmtDuration(_result!.seconds)} · ${fmtDistance(_result!.meters)}',
                style: Theme.of(context).textTheme.titleLarge),
          if (_plans.isNotEmpty) ..._planWidgets(cs),
        ]),
      ),
    );
  }

  List<Widget> _planWidgets(ColorScheme cs) {
    final p = _plans[_planIdx];
    return [
      SizedBox(
        height: 36,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (var i = 0; i < _plans.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('${fmtDuration(_plans[i].seconds)}'),
                selected: i == _planIdx,
                onSelected: (_) => setState(() => _planIdx = i),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 6),
      SizedBox(
        height: 90,
        child: ListView(children: [
          for (final l in p.legs)
            Text(l.mode == 'WALK'
                ? 'Пешком ${fmtDuration(l.seconds)}'
                : '${l.mode} ${l.route}: ${l.from} → ${l.to} (${fmtDuration(l.seconds)})'),
        ]),
      ),
    ];
  }
}
