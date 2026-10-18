import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'models.dart';
import 'services.dart';

class PickResult {
  final Place? place;
  final bool useMe;
  final bool onMap;
  PickResult({this.place, this.useMe = false, this.onMap = false});
}

Future<PickResult?> showPlacePicker(BuildContext context, LatLng bias) =>
    showDialog<PickResult>(context: context, builder: (_) => _PickerDialog(bias: bias));

class _PickerDialog extends StatefulWidget {
  final LatLng bias;
  const _PickerDialog({required this.bias});
  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  final _ctrl = TextEditingController();
  List<Place> _res = [];
  bool _loading = false;
  String? _error;

  Future<void> _go(String q) async {
    if (q.trim().isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await searchPlaces(q.trim(), widget.bias);
      if (mounted) setState(() => _res = r);
      if (r.isEmpty && mounted) setState(() => _error = 'Ничего не найдено');
    } catch (e) {
      if (mounted) setState(() => _error = 'Поиск не удался');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Выбор точки'),
      content: SizedBox(
        width: 440,
        height: 420,
        child: Column(children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            onSubmitted: _go,
            decoration: InputDecoration(
              hintText: 'Город, адрес, место',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                  onPressed: () => _go(_ctrl.text), icon: const Icon(Icons.arrow_forward)),
            ),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.my_location),
            title: const Text('Моё положение'),
            onTap: () => Navigator.pop(context, PickResult(useMe: true)),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.touch_app),
            title: const Text('Указать на карте'),
            onTap: () => Navigator.pop(context, PickResult(onMap: true)),
          ),
          const Divider(height: 1),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          Expanded(
            child: ListView(children: [
              for (final p in _res)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: p.subtitle.isEmpty
                      ? null
                      : Text(p.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, PickResult(place: p)),
                )
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена'))],
    );
  }
}
