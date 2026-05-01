import 'package:flutter/material.dart';

import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/services/admin_service.dart';
import 'package:dayday_usta/services/order_service.dart';

/// Sifariş + audit hadisələri (yalnız oxu).
class AdminWebOrderDetailScreen extends StatelessWidget {
  final String orderId;

  const AdminWebOrderDetailScreen({required this.orderId, super.key});

  @override
  Widget build(BuildContext context) {
    final orders = OrderService();
    final admin = AdminService();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Sifariş $orderId'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Ümumi'),
              Tab(text: 'Audit'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            StreamBuilder(
              stream: orders.getActiveOrderStream(orderId),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Xəta: ${snap.error}'));
                }
                if (!snap.hasData || snap.data == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final o = snap.data!;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _orderDetailRow('Status', o.status),
                    _orderDetailRow('Müştəri', o.customerId),
                    _orderDetailRow('Usta', o.masterId ?? '—'),
                    _orderDetailRow('Kateqoriya', o.category),
                    _orderDetailRow('Növ', o.type.name),
                    _orderDetailRow('Mənbə', o.source.name),
                    _orderDetailRow('Yaradılıb', o.createdAt.toString()),
                    _orderDetailRow('Ünvan (GeoPoint)', '${o.clientLocation.latitude}, ${o.clientLocation.longitude}'),
                  ],
                );
              },
            ),
            StreamBuilder(
              stream: admin.watchOrderAuditEvents(orderId),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Xəta: ${snap.error}'));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final events = snap.data!;
                if (events.isEmpty) {
                  return const Center(child: Text('Audit qeydi yoxdur.'));
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: events.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = events[i];
                    return ListTile(
                      title: Text(e.type, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${e.timestamp?.toIso8601String() ?? '—'} · actor: ${e.actorId ?? '—'}\n${e.details}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[800]),
                      ),
                      isThreeLine: true,
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

Widget _orderDetailRow(String k, String v) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(k, style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500)),
        ),
        Expanded(child: Text(v, style: const TextStyle(color: kDarkColor))),
      ],
    ),
  );
}
