import 'package:flutter/material.dart';
import 'models.dart';

/// Карточка погоды и осадков для выбранной точки.
class WeatherCard extends StatelessWidget {
  final Future<WeatherInfo> future;
  const WeatherCard({super.key, required this.future});

  Widget _chip(IconData i, String t) => Padding(
        padding: const EdgeInsets.only(right: 14, top: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 15, color: Colors.white70),
          const SizedBox(width: 4),
          Text(t, style: const TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WeatherInfo>(
      future: future,
      builder: (_, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return Container(
            height: 90,
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16)),
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError) {
          return const Text('Погода сейчас недоступна');
        }
        final w = snap.data!;
        final d = weatherDesc(w.code);
        final maxPrecip = w.hours.fold<double>(0.5, (a, h) => h.precip > a ? h.precip : a);
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: d.colors),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(d.icon, color: Colors.white, size: 46),
              const SizedBox(width: 12),
              Text('${w.temp.round()}°',
                  style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w300)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(d.label,
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  Text('Ощущается как ${w.feels.round()}°',
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ]),
              ),
            ]),
            const SizedBox(height: 8),
            Wrap(children: [
              _chip(Icons.water_drop_outlined, 'Влажность ${w.humidity.round()}%'),
              _chip(Icons.air, 'Ветер ${w.wind.toStringAsFixed(1)} м/с'),
              _chip(Icons.speed, '${w.pressureMm.round()} мм рт. ст.'),
              _chip(Icons.cloud_outlined, 'Облачность ${w.cloud.round()}%'),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white.withAlpha(40), borderRadius: BorderRadius.circular(12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Осадки',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                if (w.nowcast != null)
                  Text(w.nowcast!, style: const TextStyle(color: Colors.white)),
                Text(
                    'Сейчас: ${w.precip.toStringAsFixed(1)} мм/ч · Сегодня: '
                    '${w.daySum.toStringAsFixed(1)} мм, вероятность до ${w.dayProb.round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 13)),
                Text('Сегодня от ${w.tMin.round()}° до ${w.tMax.round()}°',
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 10),
            const Text('Ближайшие 12 часов',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final h in w.hours)
                  Container(
                    width: 50,
                    margin: const EdgeInsets.only(right: 6),
                    child: Column(children: [
                      Text('${h.hour}:00', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                      const SizedBox(height: 2),
                      Icon(weatherDesc(h.code).icon, color: Colors.white, size: 18),
                      Text('${h.temp.round()}°',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Container(
                        width: 18,
                        height: 4 + 36 * (h.precip / maxPrecip).clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                            color: const Color(0xFF80D8FF), borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(height: 2),
                      Text('${h.prob.round()}%',
                          style: const TextStyle(color: Color(0xFFB3E5FC), fontSize: 11)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 4),
            const Text('Данные: Open-Meteo', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
        );
      },
    );
  }
}
