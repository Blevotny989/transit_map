import 'package:flutter/foundation.dart';

/// Состояние запуска: приветственный экран показывает этапы и скрывается,
/// когда карта готова.
class Boot {
  static final stage = ValueNotifier<String>('Запускаю…');
  static final ready = ValueNotifier<bool>(false);
  static void set(String s) => stage.value = s;
  static void done() => ready.value = true;
}
