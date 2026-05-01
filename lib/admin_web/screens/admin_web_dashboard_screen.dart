import 'package:flutter/material.dart';

import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/services/admin_service.dart';

/// Краткая сводка для web-admin (те же источники, что и mobil Admin paneli).
class AdminWebDashboardScreen extends StatefulWidget {
  final String userId;

  const AdminWebDashboardScreen({required this.userId, super.key});

  @override
  State<AdminWebDashboardScreen> createState() => _AdminWebDashboardScreenState();
}

class _AdminWebDashboardScreenState extends State<AdminWebDashboardScreen> {
  final AdminService _admin = AdminService();

  late Future<int> _clientCountFuture;
  late Future<int> _masterCountFuture;
  late Future<Map<String, int>> _dailyStatsFuture;

  @override
  void initState() {
    super.initState();
    _reloadStats();
  }

  /// Yenidən yükləmək üçün (məs. çəkmə / düymə) — eyni Future obyektləri təkrarlanmasın deyə burada yaranır.
  void _reloadStats() {
    _clientCountFuture = _admin.getClientCount();
    _masterCountFuture = _admin.getMasterCount();
    _dailyStatsFuture = _admin.getDailyStatistics();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('UID: ${widget.userId}', style: TextStyle(color: Colors.grey[700], fontSize: 13)),
              const SizedBox(height: 16),
              const Text(
                'Qısa statistika',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kDarkColor),
              ),
              const SizedBox(height: 16),
              FutureBuilder<int>(
                future: _clientCountFuture,
                builder: (context, snap) => _StatTile(title: 'Müştərilər', value: snap.data?.toString() ?? '…'),
              ),
              FutureBuilder<int>(
                future: _masterCountFuture,
                builder: (context, snap) => _StatTile(title: 'Ustalar', value: snap.data?.toString() ?? '…'),
              ),
              FutureBuilder<Map<String, int>>(
                future: _dailyStatsFuture,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    return const _StatTile(title: 'Son 24 saat', value: '…');
                  }
                  final m = snap.data!;
                  return Column(
                    children: [
                      _StatTile(title: 'Yeni müştəri (24s)', value: '${m['newClients']}'),
                      _StatTile(title: 'Yeni usta (24s)', value: '${m['newMasters']}'),
                      _StatTile(title: 'Yeni sifariş (24s)', value: '${m['newEmergencyOrders']}'),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String title;
  final String value;

  const _StatTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title),
        trailing: Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
