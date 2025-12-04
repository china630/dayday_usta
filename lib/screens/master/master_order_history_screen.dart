import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/services/order_service.dart';

class MasterOrderHistoryScreen extends StatelessWidget {
  final String masterId;

  const MasterOrderHistoryScreen({required this.masterId, super.key});

  // Имитация метода для получения истории заказов Мастера
  Stream<List<app_order.Order>> _getMasterOrderHistoryStream() {
    // В реальном проекте: OrderService().getOrderHistoryStream(masterId, role: AppConstants.roleMaster);

    // Заглушка: Возвращаем список заказов, связанных с этим Мастером
    final mockOrders = [
      app_order.Order(
        id: 'ORDER_003', customerId: 'CLIENT_X', category: 'Qabyuyan',
        problemDescription: 'Təmir', clientLocation: const GeoPoint(0, 0),
        status: AppConstants.orderStatusCompleted, masterId: masterId,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
      ),
      app_order.Order(
        id: 'ORDER_004', customerId: 'CLIENT_Y', category: 'Soyuducu',
        problemDescription: 'Diaqnostika', clientLocation: const GeoPoint(0, 0),
        status: AppConstants.orderStatusCancelled, masterId: masterId,
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
      ),
    ];
    return Stream.value(mockOrders);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sifarişlər Tarixçəsi')), // История Заказов
      body: StreamBuilder<List<app_order.Order>>(
        stream: _getMasterOrderHistoryStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Tarixçədə sifariş tapılmadı.')); // Заказов не найдено
          }

          final orders = snapshot.data!;
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return _buildOrderItem(context, order);
            },
          );
        },
      ),
    );
  }

  Widget _buildOrderItem(BuildContext context, app_order.Order order) {
    // *Имитация получения имени клиента по ID
    final clientName = order.customerId == 'CLIENT_X' ? 'Aynur Qədimova' : 'Sənan Babayev';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      elevation: 2,
      child: ListTile(
        title: Text('${order.category} Təmiri'), // Категория
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Klient: $clientName'), // Имя Фамилия Клиента
            Text('Tarix: ${order.createdAt.day}.${order.createdAt.month}.${order.createdAt.year}'), // Дата
            Text('Status: ${order.status == AppConstants.orderStatusCompleted ? 'Bitirilib' : 'Ləğv Edilib'}',
                style: TextStyle(color: order.status == AppConstants.orderStatusCompleted ? Colors.green : Colors.red)),
          ],
        ),
      ),
    );
  }
}