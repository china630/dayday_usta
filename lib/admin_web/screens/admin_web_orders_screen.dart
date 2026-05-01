import 'package:flutter/material.dart';

import 'package:dayday_usta/admin_web/screens/admin_web_order_detail_screen.dart';
import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/models/order.dart' as app_order;
import 'package:dayday_usta/services/admin_service.dart';

class AdminWebOrdersScreen extends StatelessWidget {
  const AdminWebOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = AdminService();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Son sifarişlər',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kDarkColor),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<app_order.Order>>(
              stream: admin.watchRecentOrdersForAdmin(limit: 80),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Xəta: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data!;
                if (list.isEmpty) {
                  return const Center(child: Text('Sifariş yoxdur.'));
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final o = list[i];
                    return ListTile(
                      title: Text('${o.category} · ${o.status}'),
                      subtitle: Text('${o.id} · ${o.createdAt}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AdminWebOrderDetailScreen(orderId: o.id),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
