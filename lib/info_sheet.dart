import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'models.dart';
import 'services.dart';

/// Краткая сводка об объекте, на который нажали на карте.
class InfoSheet extends StatefulWidget {
  final LatLng pos;
  final double zoom;
  final void Function(String name) onFrom, onTo;
  const InfoSheet(
      {super.key, required this.pos, required this.zoom, required this.onFrom, required this.onTo});

  @override
  State<InfoSheet> createState() => _InfoSheetState();
}

class _InfoSheetState extends State<InfoSheet> {
  late Future<ObjectInfo> _f;

  @override
  void initState() {
    super.initState();
    _f = loadObjectInfo(widget.pos, widget.zoom);
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      child: SingleChildScrollView(
        child: FutureBuilder<ObjectInfo>(
          future: _f,
          builder: (_, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                  padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
            }
            if (snap.hasError) {
              return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Объект', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('Не удалось получить сведения. Координаты: '
                    '${widget.pos.latitude.toStringAsFixed(5)}, ${widget.pos.longitude.toStringAsFixed(5)}'),
                const SizedBox(height: 14),
                _buttons('Точка на карте'),
              ]);
            }
            final i = snap.data!;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(i.typeLabel, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w500)),
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
                      SizedBox(
                          width: 110,
                          child: Text(f.key, style: TextStyle(color: cs.onSurfaceVariant))),
                      Expanded(child: SelectableText(f.value)),
                    ]),
                  ),
              ],
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
            ]);
          },
        ),
      ),
    );
  }
}
