import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/services/order_service.dart';
// import 'package:bolt_usta/screens/client/review_form_screen.dart'; // Для кнопки Отзыва

class CustomerOrderHistoryScreen extends StatelessWidget {
  final String customerId;

  const CustomerOrderHistoryScreen({required this.customerId, super.key});

  // Имитация метода для получения истории заказов
  Stream<List<app_order.Order>> _getOrderHistoryStream() {
    // В реальном проекте: OrderService().getOrderHistoryStream(customerId, role: AppConstants.roleCustomer);

    // Заглушка: Возвращаем список завершенных заказов
    final mockOrders = [
      app_order.Order(
        id: 'ORDER_001', customerId: customerId, category: 'Kombi',
        problemDescription: 'Təmir edildi', clientLocation: const GeoPoint(0, 0),
        status: AppConstants.orderStatusCompleted, masterId: 'MASTER_A',
        createdAt: DateTime.now().subtract(const Duration(days: 5)),
      ),
      app_order.Order(
        id: 'ORDER_002', customerId: customerId, category: 'Elektrik',
        problemDescription: 'Quraşdırma', clientLocation: const GeoPoint(0, 0),
        status: AppConstants.orderStatusCompleted, masterId: 'MASTER_B',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
    ];
    return Stream.value(mockOrders);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sifarişlər Tarixçəsi')), // История Заказов
      body: StreamBuilder<List<app_order.Order>>(
        stream: _getOrderHistoryStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Heç bir sifariş tapılmadı.')); // Заказов не найдено
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
    // *Имитация получения имени мастера по ID
    final masterName = order.masterId == 'MASTER_A' ? 'Əli Həsənov' : 'Vüsal Qəhrəmanov';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      elevation: 2,
      child: ListTile(
        title: Text('${order.category} Təmiri'), // Категория
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Usta: $masterName'), // Имя Фамилия Мастера
            Text('Tarix: ${order.createdAt.day}.${order.createdAt.month}.${order.createdAt.year}'), // Дата
            Text('Status: ${order.status == AppConstants.orderStatusCompleted ? 'Bitirilib' : 'Ləğv Edilib'}',
                style: TextStyle(color: order.status == AppConstants.orderStatusCompleted ? Colors.green : Colors.red)),
          ],
        ),
        trailing: order.status == AppConstants.orderStatusCompleted
            ? TextButton(
          onPressed: () {
            // Navigator.push(context, MaterialPageRoute(builder: (_) => ReviewFormScreen(masterId: order.masterId!, customerId: order.customerId, orderId: order.id)));
            print('Переход на Rəy Bildir');
          },
          child: const Text('Rəy Bildir'), // Оставить Отзыв
        )
            : null,
      ),
    );
  }
}