# Транспортная карта (Flutter / Dart)
Windows, Linux, macOS, Android. Данные: OpenStreetMap, Esri, EOX (Sentinel-2), HERE, 2ГИС, Яндекс.Расписания, Transitland, RainViewer, Open-Meteo, Wikipedia.
Ключи, язык, положение и кэш: значок шестерёнки. Старинная карта включается одной кнопкой на карте.
Сборка Windows: .github/workflows/build.yml (GitHub Actions).

- Спутник: Esri World Imagery (самое свежее у Esri), Clarity (чётче) и Sentinel-2 cloudless 2025.
- Кэш: память -> диск -> сеть, размер виден в настройках. Старые снимки из прежних версий не используются.
- Положение: программа спрашивает разрешение при первом запуске и затем у Windows.
