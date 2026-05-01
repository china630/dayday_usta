import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:dayday_usta/core/app_constants.dart';
import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/models/order.dart' as app_order;
import 'package:dayday_usta/services/order_service.dart';
import 'package:dayday_usta/screens/order_detail_screen.dart';
import 'package:dayday_usta/screens/order_tracking_screen.dart';

class ClientOrderHistoryScreen extends StatefulWidget {
  final String customerId;

  const ClientOrderHistoryScreen({required this.customerId, super.key});

  @override
  State<ClientOrderHistoryScreen> createState() => _ClientOrderHistoryScreenState();
}

class _ClientOrderHistoryScreenState extends State<ClientOrderHistoryScreen> {
  final OrderService _orderService = OrderService();
  bool _repeatBusy = false;

  Future<void> _repeatOrder(BuildContext context, app_order.Order order) async {
    if (_repeatBusy) return;
    setState(() => _repeatBusy = true);
    try {
      final r = await _orderService.repeatOrderFromTemplate(
        clientUserId: widget.customerId,
        template: order,
      );
      final id = r['orderId'] as String?;
      if (!context.mounted || id == null || id.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(
            orderId: id,
            masterId: null,
            clientLocation: LatLng(order.clientLocation.latitude, order.clientLocation.longitude),
          ),
        ),
      );
    } catch (e) {
      final msg = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _repeatBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('Sifarişlərim', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: StreamBuilder<List<app_order.Order>>(
        stream: _orderService.getClientOrderHistory(widget.customerId),
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
      case AppConstants.orderStatusCanceledByMaster:
        statusText = "Usta ləğv etdi";
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
    final showRepeat = order.status == AppConstants.orderStatusCompleted;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            onTap: () {
              if (order.status == AppConstants.orderStatusPending ||
                  order.status == AppConstants.orderStatusAccepted ||
                  order.status == AppConstants.orderStatusArrived) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderTrackingScreen(
                      orderId: order.id,
                      masterId: order.masterId,
                      clientLocation: LatLng(order.clientLocation.latitude, order.clientLocation.longitude),
                    ),
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderDetailScreen(order: order, isClient: true),
                  ),
                );
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
                              Text(order.category,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 16, color: kDarkColor)),
                              Text(isEmergency ? "Təcili sifariş" : "Planlı sifariş",
                                  style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
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
                      Text(dateStr,
                          style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
                      const Spacer(),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (showRepeat)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _repeatBusy ? null : () => _repeatOrder(context, order),
                  icon: _repeatBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.replay, size: 18),
                  label: const Text('Yenidən sifariş'),
                  style: OutlinedButton.styleFrom(foregroundColor: kPrimaryColor),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
