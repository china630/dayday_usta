import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/services/user_profile_service.dart';
import 'package:bolt_usta/managers/location_manager.dart';
import 'package:bolt_usta/services/order_service.dart'; // Для генератора тестовых данных

class MasterDashboardScreen extends StatelessWidget {
  final String masterId;
  final MasterProfile masterProfile; // ✅ Используется в main.dart

  const MasterDashboardScreen({
    required this.masterId,
    required this.masterProfile, // ✅ Используется в main.dart
    super.key
  });

  @override
  Widget build(BuildContext context) {
    // Используем StreamProvider для живых данных профиля мастера
    return StreamProvider<MasterProfile>(
      create: (_) => UserProfileService().getMasterProfileStream(masterId),
      initialData: masterProfile, // Используем начальный профиль, переданный из Wrapper
      child: const _MasterDashboardContent(),
    );
  }
}

class _MasterDashboardContent extends StatefulWidget {
  const _MasterDashboardContent();

  @override
  State<_MasterDashboardContent> createState() => _MasterDashboardContentState();
}

class _MasterDashboardContentState extends State<_MasterDashboardContent> {
  final AuthService _authService = AuthService();
  final UserProfileService _profileService = UserProfileService();
  final OrderService _orderService = OrderService(); // Для генерации тестовых данных

  // A1.3: Метод для ручной разблокировки (смена статуса на 'free')
  Future<void> _unlockAvailability(String masterId) async {
    try {
      await _profileService.updateMasterStatus(masterId, AppConstants.masterStatusFree);
      Provider.of<LocationManager>(context, listen: false).toggleOnlineStatus(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Статус успешно сброшен на "Свободен".')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка разблокировки: ${e.toString()}')),
      );
    }
  }

  void _openProfileEditor(MasterProfile master) {
    print('Открывает Profile Editor для ${master.fullName}');
  }

  void _openVerification() {
    print('Открывает экран “Eyniləşdirmə”');
  }

  // ✅ НОВЫЙ МЕТОД: Вызов Callable Function для генерации тестовых данных
  Future<void> _generateTestData() async {
    try {
      final count = await _orderService.generateMasterTestData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Успешно создано $count тестовых мастеров.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('СБОЙ ГЕНЕРАЦИИ: ${e.toString()}')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final master = Provider.of<MasterProfile>(context);
    final locationManager = Provider.of<LocationManager>(context);

    final isVerified = master.verificationStatus == AppConstants.verificationVerified;
    final isBlockedByRejection = master.status == AppConstants.masterStatusUnavailable;
    final isOnline = locationManager.isOnline;

    void toggleOnline(bool newValue) {
      if (isBlockedByRejection) return;
      locationManager.toggleOnlineStatus(newValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? 'Сервис запущен.' : 'Сервис остановлен.'),
        ),
      );
    }

    String getStatusText() {
      if (isBlockedByRejection) {
        return 'НЕДОСТУПЕН (БЛОКИРОВАН)';
      } else if (isOnline) {
        return 'ONLINE (Свободен)';
      } else if (master.status == AppConstants.masterStatusBusy) {
        return 'ЗАНЯТ (Активный заказ)';
      } else {
        return 'OFFLINE';
      }
    }

    Color getStatusColor() {
      if (isBlockedByRejection) return Colors.red.shade900;
      if (isOnline) return Colors.green.shade700;
      return Colors.grey.shade600;
    }


    return Scaffold(
      appBar: AppBar(
        title: const Text('Usta Paneli', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: isBlockedByRejection ? Colors.red.shade800 : Colors.blue.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              await locationManager.stopOnlineServiceOnSignOut();
              await _authService.signOut();
            },
            tooltip: 'Çıxış',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Секция Профиля
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                  radius: 40,
                  backgroundImage: NetworkImage('https://via.placeholder.com/150'),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        master.fullName,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(
                              isVerified ? Icons.verified_user : Icons.warning_amber,
                              color: isVerified ? Colors.green : Colors.orange,
                              size: 20
                          ),
                          const SizedBox(width: 5),
                          Text(
                            isVerified ? 'Eyniləşdirilib' : 'Eyniləşdirmə gözlənilir',
                            style: TextStyle(color: isVerified ? Colors.green.shade700 : Colors.orange, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // A1.2: Карточка Статуса и Счетчика Отказов
            Card(
              elevation: 4,
              color: isBlockedByRejection ? Colors.red.shade100 : (isOnline ? Colors.green.shade50 : Colors.grey.shade100),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          getStatusText(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: getStatusColor(),
                          ),
                        ),
                        // A1.3: Переключатель Online/Offline
                        Switch(
                          value: isOnline && !isBlockedByRejection,
                          onChanged: isBlockedByRejection ? null : toggleOnline,
                          activeColor: Colors.green.shade600,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // A1.2: Отображение счетчика отказов
                    if (master.consecutiveRejections > 0)
                      Text(
                        '❌ Пропущено/отменено заказов подряд: ${master.consecutiveRejections}',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // A1.1, A1.3: Предупреждение о блокировке и кнопка разблокировки
            if (isBlockedByRejection)
              _buildBlockWarningAndUnlockButton(master),

            // 3. Статистика
            const Text(
              'Statistika:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatisticCard('Baxışlar', master.viewsCount),
                _buildStatisticCard('Zənglər', master.callsCount),
                _buildStatisticCard('Yadda Saxlanılıb', master.savesCount),
              ],
            ),

            const SizedBox(height: 30),

            // ✅ ВРЕМЕННЫЙ ИНСТРУМЕНТ ДЛЯ ТЕСТИРОВАНИЯ
            ElevatedButton(
              onPressed: _generateTestData,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('⚠️ ГЕНЕРИРОВАТЬ 1000 ТЕСТОВЫХ ДАННЫХ'),
            ),
            const SizedBox(height: 20),


            // 4. Управление
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.blue),
              title: const Text('Redaktə Et (Профиль)', style: TextStyle(fontWeight: FontWeight.w500)),
              onTap: () => _openProfileEditor(master),
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
            ),
            const Divider(height: 0),
            ListTile(
              leading: const Icon(Icons.fingerprint, color: Colors.deepOrange),
              title: Text(
                isVerified ? 'Eyniləşdirmə statusu' : 'Eyniləşdir (Верифицировать)',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              onTap: _openVerification,
              trailing: const Icon(Icons.arrow_forward_ios, size: 18),
            ),
            const Divider(height: 0),
          ],
        ),
      ),
    );
  }

  // A1.1, A1.3: Карточка с предупреждением и кнопкой разблокировки
  Widget _buildBlockWarningAndUnlockButton(MasterProfile master) {
    return Card(
      color: Colors.red.shade50,
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '🛑 СРОЧНО: ТРЕБУЕТСЯ РАЗБЛОКИРОВКА',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ваш статус был автоматически изменен на "Недоступен" из-за превышения лимита пропусков/отмен. Нажмите кнопку ниже, чтобы возобновить работу.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _unlockAvailability(master.uid),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('РАЗБЛОКИРОВАТЬ И НАЧАТЬ РАБОТУ', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // Вспомогательный метод для статистики
  Widget _buildStatisticCard(String title, int count) {
    return Expanded(
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Text(
                count.toString(),
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 5),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}