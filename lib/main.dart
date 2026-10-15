import 'package:flutter/material.dart';
import 'config.dart';
import 'map_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Config.load();
  runApp(const TransitApp());
}

class TransitApp extends StatelessWidget {
  const TransitApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6FD9), brightness: b),
        cardTheme: CardThemeData(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Транспортная карта',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: ThemeMode.system,
        home: const MapScreen(),
      );
}
