import 'package:shared_preferences/shared_preferences.dart';

/// Настройки приложения. Ключи можно ввести прямо в программе (значок шестерёнки).
class Config {
  static const userAgent = 'TransitMapDesktop/1.1 (personal use)';

  /// Бесплатный ключ: https://www.transit.land/ — нужен для расписаний отправлений.
  static String transitlandKey = '';

  /// Адрес вашего OpenTripPlanner 1.x — нужен для маршрутов на транспорте по расписанию.
  static String otpUrl = '';

  static const minStopsZoom = 14.0;

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      transitlandKey = p.getString('tl_key') ?? '';
      otpUrl = p.getString('otp_url') ?? '';
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('tl_key', transitlandKey);
      await p.setString('otp_url', otpUrl);
    } catch (_) {}
  }
}
