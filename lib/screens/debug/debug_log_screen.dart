import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_functions/cloud_functions.dart'; // ✅ Добавлено
import 'package:firebase_auth/firebase_auth.dart';     // ✅ Добавлено
import 'package:dayday_usta/services/logger_service.dart';

class DebugLogScreen extends StatefulWidget {
  const DebugLogScreen({Key? key}) : super(key: key);

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  bool _isLoading = false;

  // Функция вызова симулятора на сервере
  Future<void> _simulateTopUp() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showSnack("İstifadəçi tapılmadı.", Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Вызываем функцию 'simulateTopUp' в регионе europe-west3
      await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('simulateTopUp')
          .call({
        'userId': user.uid,
        'amount': 10.0, // Сумма пополнения
      });

      _showSnack("Uğur! Balans 10 ₼ artırıldı.", Colors.green);

      // Добавляем запись в локальный лог для наглядности
      Log.i("Simulated TopUp: +10 AZN for ${user.uid}");
      setState(() {});

    } catch (e) {
      _showSnack("Xəta: $e", Colors.red);
      Log.e("TopUp Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = Log.logs;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Debug Menu"),
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: logs.join('\n')));
              _showSnack("Loglar kopyalandı.", Colors.white);
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {
              Log.clear();
              setState(() {});
            },
          )
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // --- ПАНЕЛЬ УПРАВЛЕНИЯ ---
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[850],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "Test əməliyyatları",
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _simulateTopUp,
                  icon: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.monetization_on),
                  label: Text(_isLoading ? "Emal olunur..." : "Balansı artır (+10 ₼)"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1, color: Colors.white24),

          // --- СПИСОК ЛОГОВ ---
          Expanded(
            child: logs.isEmpty
                ? const Center(child: Text("Hələ log yoxdur", style: TextStyle(color: Colors.grey)))
                : ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(color: Colors.white10, height: 1),
              itemBuilder: (context, index) {
                // Показываем новые логи сверху (обратный порядок, если нужно, или как есть)
                // Log.logs обычно добавляет в конец, так что последние внизу.
                // Если хочешь последние сверху, используй: final log = logs[logs.length - 1 - index];
                final log = logs[index];

                Color color = Colors.greenAccent;
                if (log.contains('WARN')) color = Colors.yellowAccent;
                if (log.contains('ERROR')) color = Colors.redAccent;
                if (log.contains('INFO')) color = Colors.white;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    log,
                    style: TextStyle(color: color, fontFamily: 'Courier', fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}