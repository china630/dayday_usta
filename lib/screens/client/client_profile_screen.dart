// lib/screens/client_profile_screen.dart

import 'package:flutter/material.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:provider/provider.dart';

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Получаем AuthService через Provider
    final authService = Provider.of<AuthService>(context, listen: false);
    // TODO: Замените currentUserId на реальное получение данных клиента
    const currentUserId = 'client_123';
    const phoneNumber = '+994 50 xxx xx xx';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Müştəri Profili'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.person_pin, size: 80, color: Colors.blue),
              const SizedBox(height: 16),
              const Text('Hesab Detalları', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 20),

              _buildInfoRow('ID', currentUserId),
              _buildInfoRow('Telefon', phoneNumber),
              const SizedBox(height: 40),

              // Кнопка ВЫХОДА (Çıxış)
              ElevatedButton.icon(
                icon: const Icon(Icons.exit_to_app, color: Colors.white),
                label: const Text('Çıxış', style: TextStyle(color: Colors.white)),
                onPressed: () async {
                  await authService.signOut();
                  // TODO: Navigator.pushReplacement на экран входа
                  print('Клиент вышел из системы.');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}