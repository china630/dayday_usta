import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class Log {
  // Храним последние 50 строк логов в памяти
  static final List<String> _logs = [];

  static List<String> get logs => List.unmodifiable(_logs);

  // Info (Инфо)
  static void i(String message, [String? tag]) => _log('ℹ️ INFO', message, tag);

  // Success (Успех)
  static void s(String message, [String? tag]) => _log('✅ SUCCESS', message, tag);

  // Warning (Предупреждение)
  static void w(String message, [String? tag]) => _log('⚠️ WARN', message, tag);

  // ✅ ДОБАВЛЕНО: Debug (Отладка) - исправляет ошибку Member not found: 'Log.d'
  static void d(String message, [String? tag]) => _log('🔧 DEBUG', message, tag);

  // Error (Ошибка)
  static void e(String message, [dynamic error]) {
    _log('⛔ ERROR', message, 'ERROR');
    if (error != null) _log('   Details', error.toString(), null);
  }

  static void _log(String prefix, String message, String? tag) {
    final time = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
    final tagStr = tag != null ? "[$tag] " : "";
    final fullLog = '$prefix $time $tagStr$message';

    // 1. Печатаем в консоль (для разработчика)
    if (kDebugMode) {
      developer.log(fullLog);
    }

    // 2. Сохраняем в буфер (для секретного экрана)
    _logs.insert(0, fullLog); // Добавляем в начало
    if (_logs.length > 100) {
      _logs.removeLast(); // Удаляем старые, если больше 100
    }
  }

  static void clear() => _logs.clear();
}