import 'package:flutter/material.dart';
import 'config.dart';

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
  final _key = TextEditingController(text: Config.transitlandKey);
  final _otp = TextEditingController(text: Config.otpUrl);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Настройки'),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Расписание отправлений (Transitland)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Бесплатный ключ API: регистрация на transit.land'),
          const SizedBox(height: 8),
          TextField(
              controller: _key,
              decoration: const InputDecoration(labelText: 'Ключ Transitland', border: OutlineInputBorder())),
          const SizedBox(height: 20),
          const Text('Маршруты на транспорте по расписанию (OpenTripPlanner)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Адрес вашего сервера OpenTripPlanner 1.x. Если пусто, время считается приблизительно.'),
          const SizedBox(height: 8),
          TextField(
              controller: _otp,
              decoration: const InputDecoration(
                  labelText: 'Адрес, например https://otp.example.com', border: OutlineInputBorder())),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
        FilledButton(
          onPressed: () async {
            Config.transitlandKey = _key.text.trim();
            var u = _otp.text.trim();
            while (u.endsWith('/')) {
              u = u.substring(0, u.length - 1);
            }
            Config.otpUrl = u;
            await Config.save();
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
