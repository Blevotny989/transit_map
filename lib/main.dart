import 'package:flutter/material.dart';
import 'map_screen.dart';

void main() => runApp(const TransitApp());

class TransitApp extends StatelessWidget {
  const TransitApp({super.key});

  ThemeData _theme(Brightness b) => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E6FD9), brightness: b),
        cardTheme: CardTheme(
          elevation: 3,
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
