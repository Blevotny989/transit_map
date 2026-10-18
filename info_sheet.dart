import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'models.dart';
import 'services.dart';
import 'weather_card.dart';

/// Сводка об объекте, на который нажали на карте, и погода в этой точке.
class InfoSheet extends StatefulWidget {
  final LatLng pos;
  final double zoom;
  final String? hintTitle;
  final void Function(String name) onFrom, onTo;
  const InfoSheet({
    super.key,
    required this.pos,
    required this.zoom,
    required this.onFrom,
    required this.onTo,
    this.hintTitle,
  });

  @override
  State<InfoSheet> createState() => _InfoSheetState();
}

class _InfoSheetState extends State<InfoSheet> {
  late Future<ObjectInfo> _f;
  late Future<WeatherInfo> _w;

  @override
  void initState() {
    super.initState();
    // оба запроса идут одновременно
    _f = loadObjectInfo(widget.pos, widget.zoom);
    _w = loadWeather(widget.pos);
  }

  Widget _buttons(String name) => Row(children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: () => widget.onTo(name),
                icon: const Icon(Icons.flag),
                label: const Text('Маршрут сюда'))),
        const SizedBox(width: 10),
        Expanded(
            child: OutlinedButton.icon(
                onPressed: () => widget.onFrom(name),
                icon: const Icon(Icons.trip_origin),
                label: const Text('Отсюда'))),
      ]);

  Widget _header(String title, String sub) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
        if (sub.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(sub,
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          FutureBuilder<ObjectInfo>(
            future: _f,
            builder: (_, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _header(widget.hintTitle ?? 'Загрузка…', ''),
                  const SizedBox(height: 10),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 14),
                  _buttons(widget.hintTitle ?? 'Точка на карте'),
                ]);
              }
              if (snap.hasError) {
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _header(widget.hintTitle ?? 'Точка на карте', ''),
                  const SizedBox(height: 6),
                  Text('Подробные сведения недоступны. Координаты: '
                      '${widget.pos.latitude.toStringAsFixed(5)}, ${widget.pos.longitude.toStringAsFixed(5)}'),
                  const SizedBox(height: 14),
                  _buttons(widget.hintTitle ?? 'Точка на карте'),
                ]);
              }
              final i = snap.data!;
              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _header(i.title, i.typeLabel),
                const SizedBox(height: 6),
                Text(i.address, style: TextStyle(color: cs.onSurfaceVariant)),
                const SizedBox(height: 14),
                _buttons(i.title),
                if (i.wikiImage != null) ...[
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(i.wikiImage!,
                        height: 170,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox()),
                  ),
                ],
                if (i.wikiText != null) ...[
                  const SizedBox(height: 12),
                  Text(i.wikiText!),
                  const SizedBox(height: 4),
                  Text('Источник: Википедия', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
                if (i.facts.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  for (final f in i.facts)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 110, child: Text(f.key, style: TextStyle(color: cs.onSurfaceVariant))),
                        Expanded(child: SelectableText(f.value)),
                      ]),
                    ),
                ],
              ]);
            },
          ),
          const SizedBox(height: 16),
          WeatherCard(future: _w),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                  text: '${widget.pos.latitude.toStringAsFixed(5)}, ${widget.pos.longitude.toStringAsFixed(5)}'));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Координаты скопированы')));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Копировать координаты'),
          ),
        ]),
      ),
    );
  }
}
