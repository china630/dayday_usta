import 'package:flutter/material.dart';
import '../core/app_colors.dart'; // Убедись, что этот файл существует и в нем есть kPrimaryColor

class BalanceCard extends StatelessWidget {
  final double balance;
  final double frozenBalance;
  final VoidCallback onTopUpPressed;

  const BalanceCard({
    Key? key,
    required this.balance,
    required this.frozenBalance,
    required this.onTopUpPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Вычисляем доступные средства
    final double available = balance - frozenBalance;

    return Container(
      width: double.infinity, // Растягиваем на всю ширину
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          // ✅ ИСПРАВЛЕНО: Используем kPrimaryColor вместо AppColors.primary
          colors: [kPrimaryColor, kPrimaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Balansım',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'DayDay Usta',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${available.toStringAsFixed(2)} ₼',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (frozenBalance > 0) ...[
            const SizedBox(height: 5),
            Row(
              children: [
                const Icon(Icons.ac_unit, color: Colors.white70, size: 14),
                const SizedBox(width: 4),
                Text(
                  'Dondurulub: ${frozenBalance.toStringAsFixed(2)} ₼',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onTopUpPressed,
              icon: const Icon(Icons.add_circle_outline, color: kPrimaryColor),
              label: const Text(
                'Balansı artır',
                style: TextStyle(
                    color: kPrimaryColor, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}