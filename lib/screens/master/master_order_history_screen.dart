import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/core/app_colors.dart'; // ✅ Цвета
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/screens/order_detail_screen.dart';
import 'package:bolt_usta/screens/master/master_active_order_screen.dart';

class MasterOrderHistoryScreen extends StatelessWidget {
  final String masterId;

  const MasterOrderHistoryScreen({required this.masterId, super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: kBackgroundColor,
        appBar: AppBar(
          title: const Text('Sifariş Tarixçəsi', style: TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: false, // Убрали стрелку назад (для таба)
          bottom: const TabBar(
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            labelStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            tabs: [
              Tab(text: "Aktiv"),
              Tab(text: "Bitmiş"),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OrderList(masterId: masterId, isActive: true),
            _OrderList(masterId: masterId, isActive: false),
          ],
        ),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final String masterId;
  final bool isActive;

  const _OrderList({required this.masterId, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final OrderService _orderService = OrderService();

    return StreamBuilder<List<app_order.Order>>(
      stream: _orderService.getMasterOrderHistory(masterId, isActive: isActive),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(isActive ? Icons.work_off : Icons.history, size: 80, color: Colors.grey[300]),
                const SizedBox(height: 16),
                Text(
                  isActive ? "Aktiv sifariş yoxdur" : "Tarixçə boşdur",
                  style: TextStyle(color: Colors.grey[600], fontSize: 16),
                ),
              ],
            ),
          );
        }

        final orders = snapshot.data!;

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return _buildOrderItem(context, order);
          },
        );
      },
    );
  }

  Widget _buildOrderItem(BuildContext context, app_order.Order order) {
    Color statusColor;
    String statusText;
    Color bgColor;

    switch (order.status) {
      case AppConstants.orderStatusAccepted:
        statusText = "Qəbul edilib"; statusColor = Colors.blue; bgColor = Colors.blue.withOpacity(0.1); break;
      case AppConstants.orderStatusArrived:
        statusText = "Çatdı"; statusColor = Colors.purple; bgColor = Colors.purple.withOpacity(0.1); break;
      case AppConstants.orderStatusCompleted:
        statusText = "Tamamlandı"; statusColor = Colors.green; bgColor = Colors.green.withOpacity(0.1); break;
      case AppConstants.orderStatusCancelled:
        statusText = "Ləğv edildi"; statusColor = Colors.red; bgColor = Colors.red.withOpacity(0.1); break;
      default:
        statusText = order.status; statusColor = Colors.grey; bgColor = Colors.grey.withOpacity(0.1);
    }

    final dateStr = DateFormat('dd.MM.yyyy HH:mm').format(order.createdAt);
    final isEmergency = order.type == app_order.OrderType.emergency;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (isActive && order.type == app_order.OrderType.emergency) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => MasterActiveOrderScreen(orderId: order.id)),
            );
          } else {
            Navigator.push(context, MaterialPageRoute(
                builder: (_) => OrderDetailScreen(order: order, isClient: false)
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
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle),
                        child: Icon(
                            isEmergency ? Icons.flash_on : Icons.calendar_today,
                            color: kPrimaryColor, size: 20
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
                    child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
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