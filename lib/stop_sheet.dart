import 'package:flutter/material.dart';
import 'config.dart';
import 'models.dart';
import 'services.dart';

class StopSheet extends StatefulWidget {
  final Stop stop;
  final VoidCallback onFrom, onTo;
  final void Function(RouteInfo) onShowRoute;
  const StopSheet(
      {super.key,
      required this.stop,
      required this.onFrom,
      required this.onTo,
      required this.onShowRoute});

  @override
  State<StopSheet> createState() => _StopSheetState();
}

class _StopSheetState extends State<StopSheet> {
  late Future<List<RouteInfo>> _routes;
  late Future<List<Departure>> _deps;

  @override
  void initState() {
    super.initState();
    _routes = loadRoutesAtStop(widget.stop.pos);
    _deps = loadDepartures(widget.stop.pos);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stop;
    final cs = Theme.of(context).colorScheme;
    final extra = <String>[
      if (s.tags['operator'] != null) 'Оператор: ${s.tags['operator']}',
      if (s.tags['network'] != null) 'Сеть: ${s.tags['network']}',
      if (s.tags['opening_hours'] != null) 'Часы работы: ${s.tags['opening_hours']}',
      if (s.tags['interval'] != null) 'Интервал: ${s.tags['interval']} мин',
      if (s.tags['wheelchair'] != null) 'Доступность для колясок: ${s.tags['wheelchair']}',
      if (s.tags['shelter'] == 'yes') 'Есть навес',
      if (s.tags['bench'] == 'yes') 'Есть скамейка',
    ];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (_, ctrl) => ListView(
        controller: ctrl,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Row(children: [
            CircleAvatar(backgroundColor: s.kind.color, child: Icon(s.kind.icon, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                Text(s.kind.label, style: TextStyle(color: cs.onSurfaceVariant)),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: widget.onTo, icon: const Icon(Icons.flag), label: const Text('Сюда'))),
            const SizedBox(width: 10),
            Expanded(
                child: OutlinedButton.icon(
                    onPressed: widget.onFrom,
                    icon: const Icon(Icons.trip_origin),
                    label: const Text('Отсюда'))),
          ]),
          if (extra.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final e in extra) Padding(padding: const EdgeInsets.only(bottom: 2), child: Text(e)),
          ],
          const SizedBox(height: 18),
          Text('Расписание отправлений', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          FutureBuilder<List<Departure>>(
            future: _deps,
            builder: (_, snap) {
              if (Config.transitlandKey.isEmpty) {
                return Text(
                    'Чтобы видеть расписание, введите бесплатный ключ Transitland в настройках '
                    '(значок шестерёнки на карте).',
                    style: TextStyle(color: cs.onSurfaceVariant));
              }
              if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              if (snap.hasError) return const Text('Не удалось загрузить расписание');
              final d = snap.data ?? [];
              if (d.isEmpty) {
                return Text('Для этой остановки расписание в открытых данных не найдено.',
                    style: TextStyle(color: cs.onSurfaceVariant));
              }
              return Column(children: [
                for (final x in d)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Text(x.time, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                    title: Text('${x.route}  ${x.headsign}'),
                  )
              ]);
            },
          ),
          const SizedBox(height: 14),
          Text('Маршруты через остановку', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 2),
          Text('Нажмите на маршрут, чтобы увидеть его линию на карте.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          const SizedBox(height: 6),
          FutureBuilder<List<RouteInfo>>(
            future: _routes,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) return const LinearProgressIndicator();
              if (snap.hasError) return const Text('Не удалось загрузить маршруты');
              final r = snap.data ?? [];
              if (r.isEmpty) {
                return Text('В OpenStreetMap нет данных о маршрутах для этой точки.',
                    style: TextStyle(color: cs.onSurfaceVariant));
              }
              return Column(children: [
                for (final x in r)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onTap: () => widget.onShowRoute(x),
                    leading: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration:
                          BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)),
                      child: Text(x.ref.isEmpty ? modeRu(x.mode) : x.ref,
                          style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
                    ),
                    title: Text(x.from.isNotEmpty ? '${x.from} → ${x.to}' : (x.name.isNotEmpty ? x.name : modeRu(x.mode))),
                    subtitle: Text([
                      modeRu(x.mode),
                      if (x.operator.isNotEmpty) x.operator,
                      if (x.interval.isNotEmpty) 'интервал ${x.interval} мин',
                      if (x.hours.isNotEmpty) 'часы: ${x.hours}',
                    ].join(' · ')),
                    trailing: const Icon(Icons.chevron_right),
                  )
              ]);
            },
          ),
        ],
      ),
    );
  }
}
