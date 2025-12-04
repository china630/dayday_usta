// lib/screens/admin/data_management_screen.dart

import 'package:flutter/material.dart';
import 'package:bolt_usta/services/data_management_service.dart';

class DataManagementScreen extends StatelessWidget {
  final String collectionName; // 'categories' или 'districts'
  final String title; // "Управление Категориями" или "Управление Районами"

  const DataManagementScreen({
    required this.collectionName,
    required this.title,
    super.key,
  });

  // В реальном проекте здесь будет StreamBuilder и UI для добавления/удаления
  // Используйте DataManagementService для реализации.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Text('UI для управления коллекцией "$collectionName"'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Логика добавления нового элемента
          print('Открыть диалог для добавления нового элемента в $collectionName');
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}