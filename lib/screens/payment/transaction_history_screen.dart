import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../core/app_colors.dart'; // Убедитесь, что kPrimaryColor доступен

class TransactionHistoryScreen extends StatelessWidget {
  final String userId;

  const TransactionHistoryScreen({Key? key, required this.userId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ✅ ИСПРАВЛЕНИЕ 1: Шапка в стиле приложения
      appBar: AppBar(
        title: const Text(
          "Ödəniş Tarixçəsi",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: kPrimaryColor, // Фирменный цвет
        foregroundColor: Colors.white,  // Белый текст и стрелка
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: kBackgroundColor,
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('transactions')
            .where('userId', isEqualTo: userId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          // 1. Загрузка
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: kPrimaryColor));
          }

          // ✅ ИСПРАВЛЕНИЕ 2: Показываем ошибку (скорее всего, проблема с индексом)
          if (snapshot.hasError) {
            print("Transaction Error: ${snapshot.error}"); // Для консоли
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  "Məlumatları yükləmək mümkün olmadı.\n(Xəta: ${snapshot.error})",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          // 2. Пусто
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 10),
                  const Text("Hələ ki, əməliyyat yoxdur", style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;

          return ListView.separated(
            padding: const EdgeInsets.all(15),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final amount = (data['amount'] ?? 0).toDouble();
              final description = data['description'] ?? 'Əməliyyat';
              final type = data['type'] ?? 'unknown';

              // Дата
              Timestamp? ts = data['createdAt'];
              String dateStr = ts != null
                  ? DateFormat('dd MMM HH:mm').format(ts.toDate())
                  : '';

              // Оформление
              final isPositive = amount > 0;
              final color = isPositive ? Colors.green : Colors.red;
              final sign = isPositive ? '+' : '';

              IconData icon;
              if (type == 'bonus') icon = Icons.card_giftcard;
              else if (type == 'topup') icon = Icons.account_balance_wallet;
              else if (type == 'penalty') icon = Icons.warning_amber_rounded;
              else icon = Icons.payment;

              return Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 5, offset: const Offset(0, 2))
                  ],
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: color.withOpacity(0.1),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  title: Text(
                    description,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    dateStr,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  trailing: Text(
                    "$sign${amount.toStringAsFixed(2)} ₼",
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}