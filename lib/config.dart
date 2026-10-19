import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppLang {
  final String code, name;
  const AppLang(this.code, this.name);
}

/// Настройки приложения. Всё меняется в программе: значок шестерёнки.
class Config {
  static const userAgent = 'TransitMapDesktop/1.2 (personal use)';

  /// Язык названий и поиска.
  static String lang = 'ru';

  /// Оформление: 'modern' или 'pirate' (старинная карта).
  static final ValueNotifier<String> theme = ValueNotifier('modern');
  static bool get pirate => theme.value == 'pirate';

  /// Ключи API (можно несколько через запятую или с новой строки).
  static String hereKeys = '';
  static String gisKeys = '';
  static String yandexKeys = '';
  static String transitlandKey = '';

  /// Адрес своего OpenTripPlanner 1.x (необязательно).
  static String otpUrl = '';

  /// Остановки грузятся при масштабе от этого значения, станции и вокзалы — раньше.
  static const minStopsZoom = 14.0;
  static const minStationsZoom = 10.0;

  /// Определять положение при запуске (Windows спросит разрешение один раз).
  static bool autoLocate = true;

  /// Морские чудовища, легенды и линии румбов на старинной карте.
  static bool seaLore = true;

  /// Последний вид карты: при следующем запуске карта откроется там же.
  static double? lastLat, lastLon;
  static double lastZoom = 12;
  static String baseName = 'scheme';
  static String prevBaseName = 'scheme';

  /// Вопрос про положение уже задавали (при первом запуске).
  static bool locAsked = false;

  static const languages = <AppLang>[
    AppLang('ru', 'Русский'),
    AppLang('en', 'English'),
    AppLang('de', 'Deutsch'),
    AppLang('fr', 'Français'),
    AppLang('es', 'Español'),
    AppLang('it', 'Italiano'),
    AppLang('pt', 'Português'),
    AppLang('pl', 'Polski'),
    AppLang('tr', 'Türkçe'),
    AppLang('uk', 'Українська'),
    AppLang('be', 'Беларуская'),
    AppLang('kk', 'Қазақша'),
    AppLang('uz', 'Oʻzbekcha'),
    AppLang('az', 'Azərbaycanca'),
    AppLang('hy', 'Հայերեն'),
    AppLang('ka', 'ქართული'),
    AppLang('zh', '中文'),
    AppLang('ja', '日本語'),
    AppLang('ko', '한국어'),
    AppLang('ar', 'العربية'),
    AppLang('he', 'עברית'),
  ];

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      lang = p.getString('lang') ?? 'ru';
      theme.value = p.getString('theme') ?? 'modern';
      hereKeys = p.getString('here_keys') ?? '';
      gisKeys = p.getString('gis_keys') ?? '';
      yandexKeys = p.getString('yandex_keys') ?? '';
      transitlandKey = p.getString('tl_key') ?? '';
      otpUrl = p.getString('otp_url') ?? '';
      autoLocate = p.getBool('auto_locate') ?? true;
      seaLore = p.getBool('sea_lore') ?? true;
      lastLat = p.getDouble('last_lat');
      lastLon = p.getDouble('last_lon');
      lastZoom = p.getDouble('last_zoom') ?? 12;
      baseName = p.getString('base') ?? 'scheme';
      prevBaseName = p.getString('prev_base') ?? 'scheme';
      locAsked = p.getBool('loc_asked') ?? false;
    } catch (_) {}
  }

  /// Быстро сохраняет только вид карты (центр, масштаб, выбранный слой).
  static Future<void> saveView() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (lastLat != null && lastLon != null) {
        await p.setDouble('last_lat', lastLat!);
        await p.setDouble('last_lon', lastLon!);
      }
      await p.setDouble('last_zoom', lastZoom);
      await p.setString('base', baseName);
      await p.setString('prev_base', prevBaseName);
      await p.setBool('loc_asked', locAsked);
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('lang', lang);
      await p.setString('theme', theme.value);
      await p.setString('here_keys', hereKeys);
      await p.setString('gis_keys', gisKeys);
      await p.setString('yandex_keys', yandexKeys);
      await p.setString('tl_key', transitlandKey);
      await p.setString('otp_url', otpUrl);
      await p.setBool('auto_locate', autoLocate);
      await p.setBool('sea_lore', seaLore);
      await p.setBool('loc_asked', locAsked);
      await p.setString('prev_base', prevBaseName);
      await p.setString('base', baseName);
    } catch (_) {}
  }
}
