/// Настройки приложения.
class Config {
  /// Обязательно укажите свой идентификатор: публичные серверы OSM
  /// блокируют запросы без нормального User-Agent.
  static const userAgent = 'TransitMapApp/1.0 (contact: you@example.com)';

  /// Бесплатный ключ: https://www.transit.land/ (раздел API).
  /// Нужен для реальных расписаний (GTFS) в выбранной остановке.
  static const transitlandKey = '';

  /// Адрес вашего OpenTripPlanner 1.x, например https://otp.example.com
  /// Нужен для маршрутов на общественном транспорте с пересадками.
  static const otpUrl = '';

  /// Остановки грузятся, только когда карта приближена не меньше этого зума.
  static const minStopsZoom = 14.0;
}
