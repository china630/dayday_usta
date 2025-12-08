import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/core/app_colors.dart'; // ✅ Цвета
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/screens/order_detail_screen.dart';
import 'package:bolt_usta/screens/order_tracking_screen.dart';

class ClientOrderHistoryScreen extends StatelessWidget {
  final String customerId;

  const ClientOrderHistoryScreen({required this.customerId, super.key});

  @override
  Widget build(BuildContext context) {
    final OrderService _orderService = OrderService();

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Sifarişlərim', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false, // Убираем стрелку назад, так как это таб
      ),
      body: StreamBuilder<List<app_order.Order>>(
        stream: _orderService.getClientOrderHistory(customerId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Xəta baş verdi', style: TextStyle(color: Colors.grey[600])));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 80, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text('Sifariş tarixçəsi boşdur', style: TextStyle(color: Colors.grey[600], fontSize: 16)),
                ],
              ),
            );
          }

          final orders = snapshot.data!;

          return ListView.builder(
            itemCount: orders.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
    // Настройка цветов и текста статуса
    Color statusColor;
    String statusText;
    Color bgColor;

    switch (order.status) {
      case AppConstants.orderStatusPending:
        statusText = "Gözləyir";
        statusColor = Colors.orange[800]!;
        bgColor = Colors.orange[50]!;
        break;
      case AppConstants.orderStatusAccepted:
        statusText = "Qəbul edilib";
        statusColor = Colors.blue[800]!;
        bgColor = Colors.blue[50]!;
        break;
      case AppConstants.orderStatusArrived:
        statusText = "Usta Çatdı";
        statusColor = Colors.purple[800]!;
        bgColor = Colors.purple[50]!;
        break;
      case AppConstants.orderStatusCompleted:
        statusText = "Tamamlandı";
        statusColor = Colors.green[800]!;
        bgColor = Colors.green[50]!;
        break;
      case AppConstants.orderStatusCancelled:
        statusText = "Ləğv edildi";
        statusColor = Colors.red[800]!;
        bgColor = Colors.red[50]!;
        break;
      default:
        statusText = order.status;
        statusColor = Colors.grey[800]!;
        bgColor = Colors.grey[100]!;
    }

    final dateStr = DateFormat('dd.MM.yyyy • HH:mm').format(order.createdAt);
    final isEmergency = order.type == app_order.OrderType.emergency;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          // Логика навигации: Активные -> Трекинг, Завершенные -> Детали
          if (order.status == AppConstants.orderStatusPending ||
              order.status == AppConstants.orderStatusAccepted ||
              order.status == AppConstants.orderStatusArrived) {

            Navigator.push(context, MaterialPageRoute(
                builder: (_) => OrderTrackingScreen(
                    orderId: order.id,
                    masterId: order.masterId,
                    clientLocation: LatLng(order.clientLocation.latitude, order.clientLocation.longitude)
                )
            ));
          } else {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => OrderDetailScreen(order: order, isClient: true)
            ));
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Иконка и Категория
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: kPrimaryColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isEmergency ? Icons.flash_on : Icons.calendar_today,
                          color: kPrimaryColor,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.category, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kDarkColor)),
                          Text(isEmergency ? "Təcili sifariş" : "Planlı sifariş", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                  // Статус (Бейдж)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      statusText,
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),

              const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),

              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey[400]),
                  const SizedBox(width: 6),
                  Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
                  const Spacer(),
                  const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}