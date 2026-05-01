import 'package:flutter/material.dart';

import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/models/master_profile.dart';
import 'package:dayday_usta/screens/admin/admin_verification_screen.dart';
import 'package:dayday_usta/services/admin_service.dart';

class AdminWebVerificationsScreen extends StatelessWidget {
  const AdminWebVerificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final admin = AdminService();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gözləyən təsdiqlər',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kDarkColor),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: StreamBuilder<List<MasterProfile>>(
              stream: admin.getPendingVerificationMasters(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Xəta: ${snapshot.error}'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = snapshot.data!;
                if (list.isEmpty) {
                  return const Center(child: Text('Gözləyən sorğu yoxdur.'));
                }
                return ListView.separated(
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final m = list[i];
                    return ListTile(
                      title: Text(m.fullName),
                      subtitle: Text(m.uid),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(context).push<bool>(
                          MaterialPageRoute(
                            builder: (_) => AdminVerificationScreen(masterProfile: m),
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
