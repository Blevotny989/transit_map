import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'config.dart';
import 'splash.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.load();
  runApp(const TransitApp());
}

class TransitApp extends StatelessWidget {
  const TransitApp({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String>(
        valueListenable: Config.theme,
        builder: (_, t, __) {
          final pirate = t == 'pirate';
          return MaterialApp(
            title: 'Транспортная карта',
            debugShowCheckedModeBanner: false,
            theme: pirate ? pirateTheme() : modernTheme(Brightness.light),
            darkTheme: pirate ? pirateTheme() : modernTheme(Brightness.dark),
            themeMode: pirate ? ThemeMode.light : ThemeMode.system,
            home: const BootGate(),
          );
        },
      );
}
