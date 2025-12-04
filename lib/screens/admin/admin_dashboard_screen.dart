// lib/screens/admin/admin_dashboard_screen.dart (ВОССТАНОВЛЕННАЯ СТРУКТУРА)

import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/admin_service.dart';
// ✅ НОВЫЙ ИМПОРТ: Для аутентификации и генерации данных
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';


class AdminDashboardScreen extends StatefulWidget {
  final String currentUserId;

  const AdminDashboardScreen({
    required this.currentUserId,
    super.key
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final AdminService _adminService = AdminService();
  final OrderService _orderService = OrderService();
  final AuthService _authService = AuthService(); // ✅ ДОБАВЛЕНО

  // Общая статистика
  Future<int>? _totalClientsFuture;
  Future<int>? _totalMastersFuture;

  // Ежедневная статистика
  Future<Map<String, int>>? _dailyStatsFuture;

  @override
  void initState() {
    super.initState();
    _loadAllStatistics();
  }

  void _loadAllStatistics() {
    setState(() {
      _totalClientsFuture = _adminService.getClientCount();
      _totalMastersFuture = _adminService.getMasterCount();
      _dailyStatsFuture = _adminService.getDailyStatistics();
    });
  }

  // ✅ НОВЫЙ МЕТОД: Вызов Callable Function для генерации тестовых данных
  Future<void> _generateTestData() async {
    if (!mounted) return;
    try {
      // NOTE: Временное решение: вызываем, предполагая, что проверка безопасности временно отключена
      final count = await _orderService.generateMasterTestData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Успешно создано $count тестовых документов.')),
      );
      _loadAllStatistics();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('СБОЙ ГЕНЕРАЦИИ: ${e.toString()}')),
      );
    }
  }

  // Временная функция для установки админ-прав (для выхода/входа)
  Future<void> _callSetAdminClaim() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final FirebaseFunctions functions = FirebaseFunctions.instanceFor(region: 'europe-west3');

    try {
      await functions.httpsCallable('setAdminClaimTemp').call();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Права установлены. Выходим...') ),
        );
      }
      await _authService.signOut(); // Запускаем выход для получения нового токена

    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка установки прав: ${e.message}')),
        );
      }
    }
  }


  void _openVerificationScreen(MasterProfile master) {
    print('Открывает Экран Eyniləşdirmə для: ${master.fullName}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Paneli', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllStatistics,
            tooltip: 'Yenilə',
          ),
          // ✅ ДОБАВЛЕНО: Кнопка установки прав (для входа/выхода)
          IconButton(
            icon: const Icon(Icons.security, color: Colors.deepOrange),
            onPressed: _callSetAdminClaim,
            tooltip: 'Admin Yetkisini Qur (Установить админ-права)',
          ),
          // ✅ ДОБАВЛЕНО: Кнопка выхода
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              // NOTE: При выходе нужно перенаправить на экран входа
              await _authService.signOut();
            },
            tooltip: 'Çıxış (Выход)',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -----------------------------------------------------------
            // 1. Секция "Ümumi Statistika" (Общая Статистика)
            // -----------------------------------------------------------
            _buildSectionTitle('Ümumi Statistika'),
            _buildOverallStats(),
            const SizedBox(height: 30),

            // -----------------------------------------------------------
            // 2. Секция "Gündəlik Statistika" (Ежедневная Статистика)
            // -----------------------------------------------------------
            _buildSectionTitle('Gündəlik Statistika (Son 24 saat)'),
            _buildDailyStats(),
            const SizedBox(height: 30),

            // -----------------------------------------------------------
            // 3. Секция "Eyniləşdirmə" (Верификация)
            // -----------------------------------------------------------
            _buildSectionTitle('Eyniləşdirmə (Gözləyir)'),
            _buildVerificationList(),
            const SizedBox(height: 30),

            // ✅ 4. Секция "Служебные Функции" (Генерация Теста)
            _buildSectionTitle('🛠️ Служебные Функции'),
            ElevatedButton.icon(
              onPressed: _generateTestData,
              icon: const Icon(Icons.download),
              label: const Text('ГЕНЕРИРОВАТЬ 1000 ТЕСТОВЫХ МАСТЕРОВ'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
            ),

          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // ВСПОМОГАТЕЛЬНЫЕ UI-ВИДЖЕТЫ (Добавлены для полноты файла)
  // --------------------------------------------------------------------------

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  Widget _buildOverallStats() {
    return Row(
      children: [
        _buildStatCard(_totalClientsFuture!, 'Klientlər', Icons.people_alt),
        const SizedBox(width: 10),
        _buildStatCard(_totalMastersFuture!, 'Ustalar', Icons.engineering),
      ],
    );
  }

  Widget _buildDailyStats() {
    return FutureBuilder<Map<String, int>>(
      future: _dailyStatsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) return const Text('Məlumat yoxdur.');

        final data = snapshot.data!;
        return Row(
          children: [
            _buildSingleDailyStat('Yeni Klient', data['newClients'] ?? 0, Colors.blue),
            const SizedBox(width: 10),
            _buildSingleDailyStat('Yeni Usta', data['newMasters'] ?? 0, Colors.orange),
            const SizedBox(width: 10),
            _buildSingleDailyStat('Təcili Sifariş', data['newEmergencyOrders'] ?? 0, Colors.red),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(Future<int> future, String title, IconData icon) {
    return Expanded(
      child: Card(
        elevation: 4,
        child: FutureBuilder<int>(
          future: future,
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                children: [
                  Icon(icon, size: 30, color: Colors.blue.shade700),
                  const SizedBox(height: 5),
                  Text(count.toString(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSingleDailyStat(String title, int count, Color color) {
    return Expanded(
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            children: [
              Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
              const SizedBox(height: 3),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationList() {
    return StreamBuilder<List<MasterProfile>>(
      stream: _adminService.getPendingVerificationMasters(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('Gözləyən usta yoxdur.'));
        }

        final masters = snapshot.data!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: masters.length,
          itemBuilder: (context, index) {
            final master = masters[index];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(master.fullName ?? 'Naməlum Usta'),
              subtitle: Text(master.phoneNumber),
              trailing: ElevatedButton(
                onPressed: () => _openVerificationScreen(master),
                child: const Text('Yoxla'),
              ),
            );
          },
        );
      },
    );
  }
}