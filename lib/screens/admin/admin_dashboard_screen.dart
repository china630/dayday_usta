import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/core/app_colors.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/admin_service.dart';
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/screens/admin/admin_verification_screen.dart';
import 'package:bolt_usta/screens/auth/auth_screen.dart';
// ✅ ИСПРАВЛЕН ИМПОРТ (добавлена точка с запятой)
import 'package:bolt_usta/screens/debug/debug_log_screen.dart';

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
  final AuthService _authService = AuthService();

  // Счетчик для секретного меню
  int _debugTapCount = 0;

  // Статистика
  Future<int>? _totalClientsFuture;
  Future<int>? _totalMastersFuture;
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

  Future<void> _generateTestData() async {
    if (!mounted) return;
    try {
      final count = await _orderService.generateMasterTestData();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Uğurla yaradıldı: $count test ustası')),
      );
      _loadAllStatistics();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Xəta: ${e.toString()}')),
      );
    }
  }

  // Логика выхода
  Future<void> _signOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
            (route) => false,
      );
    }
  }

  void _openVerificationScreen(MasterProfile master) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AdminVerificationScreen(masterProfile: master)),
    );
    if (result == true) {
      _loadAllStatistics();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        // ✅ ИСПРАВЛЕНА ВЛОЖЕННОСТЬ (GestureDetector закрыт правильно)
        title: GestureDetector(
          onTap: () {
            _debugTapCount++;
            if (_debugTapCount >= 5) {
              _debugTapCount = 0;
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogScreen()));
            }
          },
          child: const Text('Admin Paneli', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAllStatistics,
            tooltip: 'Yenilə',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
            tooltip: 'Çıxış',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Общая статистика
            _buildSectionTitle('Ümumi Statistika'),
            _buildOverallStats(),
            const SizedBox(height: 30),

            // 2. Ежедневная статистика
            _buildSectionTitle('Gündəlik Statistika (Son 24 saat)'),
            _buildDailyStats(),
            const SizedBox(height: 30),

            // 3. Список верификации
            Row(
              children: [
                const Icon(Icons.verified_user, color: kPrimaryColor),
                const SizedBox(width: 8),
                Text('Eyniləşdirmə (Gözləyir)', style: _titleStyle()),
              ],
            ),
            const SizedBox(height: 15),
            _buildVerificationList(),

            const SizedBox(height: 40),

            // 4. Служебные функции
            ExpansionTile(
              title: const Text("🛠️ Служебные функции (Тест)", style: TextStyle(fontWeight: FontWeight.bold)),
              children: [
                Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generateTestData,
                      icon: const Icon(Icons.download, color: Colors.white),
                      label: const Text('1000 TEST USTASI YARAT'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- UI WIDGETS ---

  TextStyle _titleStyle() => const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor);

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Text(title, style: _titleStyle()),
    );
  }

  Widget _buildOverallStats() {
    return Row(
      children: [
        _buildStatCard(_totalClientsFuture!, 'Klientlər', Icons.people_alt, Colors.blue),
        const SizedBox(width: 15),
        _buildStatCard(_totalMastersFuture!, 'Ustalar', Icons.engineering, kPrimaryColor),
      ],
    );
  }

  Widget _buildStatCard(Future<int> future, String title, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        ),
        child: FutureBuilder<int>(
          future: future,
          builder: (context, snapshot) {
            final count = snapshot.data ?? 0;
            return Column(
              children: [
                Icon(icon, size: 30, color: color),
                const SizedBox(height: 10),
                Text(count.toString(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: kDarkColor)),
                const SizedBox(height: 5),
                Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildDailyStats() {
    return FutureBuilder<Map<String, int>>(
      future: _dailyStatsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
        }
        final data = snapshot.data ?? {};
        return Row(
          children: [
            _buildSingleDailyStat('Yeni Klient', data['newClients'] ?? 0, Colors.blue),
            const SizedBox(width: 10),
            _buildSingleDailyStat('Yeni Usta', data['newMasters'] ?? 0, Colors.orange),
            const SizedBox(width: 10),
            _buildSingleDailyStat('Sifarişlər', data['newEmergencyOrders'] ?? 0, kPrimaryColor),
          ],
        );
      },
    );
  }

  Widget _buildSingleDailyStat(String title, int count, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Text(count.toString(), style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 5),
            Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey[600]), maxLines: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationList() {
    return StreamBuilder<List<MasterProfile>>(
      stream: _adminService.getPendingVerificationMasters(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)),
            child: const Center(child: Text('Gözləyən usta yoxdur.', style: TextStyle(color: Colors.grey))),
          );
        }

        final masters = snapshot.data!;
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: masters.length,
          itemBuilder: (context, index) {
            final master = masters[index];
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: Colors.white,
              child: ListTile(
                contentPadding: const EdgeInsets.all(10),
                leading: CircleAvatar(
                  backgroundColor: kBackgroundColor,
                  child: const Icon(Icons.person, color: Colors.grey),
                ),
                title: Text(master.fullName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(master.phoneNumber),
                trailing: ElevatedButton(
                  onPressed: () => _openVerificationScreen(master),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('YOXLA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        );
      },
    );
  }
}