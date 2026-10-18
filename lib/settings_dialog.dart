import 'package:flutter/material.dart';
import 'config.dart';
import 'disk_cache.dart';
import 'services.dart';
import 'tile_cache.dart';

Future<void> showSettings(BuildContext context) => showDialog(
      context: context,
      builder: (_) => const _SettingsDialog(),
    );

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog();
  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  final _here = TextEditingController(text: Config.hereKeys);
  final _gis = TextEditingController(text: Config.gisKeys);
  final _yandex = TextEditingController(text: Config.yandexKeys);
  final _tl = TextEditingController(text: Config.transitlandKey);
  final _otp = TextEditingController(text: Config.otpUrl);
  String _lang = Config.lang;
  String _theme = Config.theme.value;
  bool _cleared = false;

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 6),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _field(TextEditingController c, String label, String hint) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final small = TextStyle(color: cs.onSurfaceVariant, fontSize: 12);
    return AlertDialog(
      title: const Text('Настройки'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _title('Язык названий и поиска'),
            DropdownButtonFormField<String>(
              value: _lang,
              isExpanded: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
              items: [
                for (final l in Config.languages) DropdownMenuItem(value: l.code, child: Text('${l.name}  (${l.code})'))
              ],
              onChanged: (v) => setState(() => _lang = v ?? 'ru'),
            ),
            const SizedBox(height: 4),
            Text('Названия мест и остановок показываются на этом языке, а искать можно на любом. '
                'Интерфейс программы остаётся русским.',
                style: small),
            _title('Оформление'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'modern', label: Text('Современное'), icon: Icon(Icons.map_outlined)),
                ButtonSegment(value: 'pirate', label: Text('Старинная карта'), icon: Icon(Icons.sailing)),
              ],
              selected: {_theme},
              onSelectionChanged: (s) => setState(() => _theme = s.first),
            ),
            _title('Ключи API для расписаний и маршрутов'),
            Text('Можно вписать несколько ключей через запятую или с новой строки: если у одного кончится лимит, '
                'возьмётся следующий. Для стран СНГ сначала пробуются 2ГИС и Яндекс.Расписания, '
                'для остального мира HERE и Transitland. Без ключей маршруты строятся по данным OpenStreetMap.',
                style: small),
            _field(_here, 'HERE (весь мир): маршруты и отправления', 'developer.here.com'),
            _field(_tl, 'Transitland (весь мир): отправления', 'transit.land'),
            _field(_gis, '2ГИС (СНГ): маршруты на транспорте', 'platform.2gis.ru, демо-ключ'),
            _field(_yandex, 'Яндекс.Расписания (СНГ): отправления', 'developer.tech.yandex.ru'),
            _field(_otp, 'OpenTripPlanner (необязательно)', 'https://otp.example.com'),
            _title('Кэш'),
            Row(children: [
              OutlinedButton.icon(
                onPressed: () async {
                  await DiskCache.clear();
                  stopStore.clearMemory();
                  stationStore.clearMemory();
                  bigPlaceStore.clearMemory();
                  smallPlaceStore.clearMemory();
                  await initTileCache();
                  if (mounted) setState(() => _cleared = true);
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Очистить кэш карты'),
              ),
              const SizedBox(width: 10),
              if (_cleared) const Text('Готово'),
            ]),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            Config.lang = _lang;
            Config.hereKeys = _here.text.trim();
            Config.gisKeys = _gis.text.trim();
            Config.yandexKeys = _yandex.text.trim();
            Config.transitlandKey = _tl.text.trim();
            var u = _otp.text.trim();
            while (u.endsWith('/')) {
              u = u.substring(0, u.length - 1);
            }
            Config.otpUrl = u;
            Config.theme.value = _theme;
            await Config.save();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
