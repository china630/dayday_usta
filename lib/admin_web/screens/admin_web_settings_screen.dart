import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'package:dayday_usta/core/app_colors.dart';

/// Read-only `system_settings/global` (yazış Rules ilə bağlıdır).
class AdminWebSettingsScreen extends StatelessWidget {
  const AdminWebSettingsScreen({super.key});

  String _maskUrl(String? raw) {
    if (raw == null || raw.isEmpty) return '— (boş)';
    if (raw.length <= 24) return raw;
    return '${raw.substring(0, 16)}…${raw.substring(raw.length - 6)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('system_settings').doc('global').get(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(child: Text('Xəta: ${snap.error}'));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final doc = snap.data!;
          if (!doc.exists || doc.data() == null) {
            return const Center(
              child: Text('system_settings/global sənədi yoxdur və ya boşdur.'),
            );
          }
          final data = doc.data()!;
          final keys = data.keys.toList()..sort();

          return Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'system_settings / global',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kDarkColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Yalnız oxu. Dəyişiklik: Firebase Console və ya gələcək admin CF.',
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: keys.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final k = keys[i];
                        final v = data[k];
                        final display = k == 'adminWebhookUrl' && v is String
                            ? _maskUrl(v)
                            : v.toString();
                        return ListTile(
                          title: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: SelectableText(display),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
