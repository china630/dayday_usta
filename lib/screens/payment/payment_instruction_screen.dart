import 'package:flutter/material.dart';
import '../../core/app_colors.dart'; // Убедись, что тут есть kPrimaryColor

class PaymentInstructionScreen extends StatelessWidget {
  final String userPhoneNumber;

  const PaymentInstructionScreen({Key? key, required this.userPhoneNumber}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Balansı artır'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // ❌ Было: const Icon(..., color: AppColors.primary)
            // ✅ Стало: Icon(..., color: kPrimaryColor) - убрали const и исправили имя
            Icon(Icons.payment, size: 80, color: kPrimaryColor),

            const SizedBox(height: 20),
            const Text(
              'MilliÖn terminalı vasitəsilə',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            _buildStep(1, 'Yaxınlıqdaki MilliÖn terminalına yaxınlaşın'),
            _buildStep(2, '"DayDay Usta" xidmətini seçin'),
            _buildStep(3, 'Nömrənizi daxil edin: $userPhoneNumber'),
            _buildStep(4, 'Ödənişi edin (min. 1 AZN)'),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Balansınız ödənişdən dərhal sonra avtomatik artacaq.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(int number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: kPrimaryColor, // ✅ Исправлено на kPrimaryColor
            radius: 14,
            child: Text('$number', style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }
}