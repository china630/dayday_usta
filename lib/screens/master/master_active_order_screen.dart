import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/models/user_profile.dart';
import 'package:bolt_usta/services/order_service.dart';
// ✅ ИСПРАВЛЕНИЕ: Используем правильный сервис для получения профилей
import 'package:bolt_usta/services/user_profile_service.dart';

class MasterActiveOrderScreen extends StatefulWidget {
  final String orderId;

  const MasterActiveOrderScreen({required this.orderId, super.key});

  @override
  State<MasterActiveOrderScreen> createState() => _MasterActiveOrderScreenState();
}

class _MasterActiveOrderScreenState extends State<MasterActiveOrderScreen> {
  final OrderService _orderService = OrderService();
  // ✅ ИСПРАВЛЕНИЕ: Инициализируем UserProfileService
  final UserProfileService _userProfileService = UserProfileService();

  // Логика обновления статуса
  Future<void> _updateStatus(String newStatus) async {
    try {
      if (newStatus == AppConstants.orderStatusArrived) {
        await _orderService.masterArrived(widget.orderId);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status yeniləndi: Çatdım.')));
      } else if (newStatus == AppConstants.orderStatusCompleted) {
        await _orderService.masterCompleteOrder(widget.orderId);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sifariş uğurla bitirildi.')));
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      setState(() {});
    } catch (e) {
      print('Ошибка обновления статуса: $e');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Xəta baş verdi. Status dəyişmədi.')));
    }
  }

  // Логика отмены
  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sifarişi Ləğv Et'),
        content: const Text('Ləğv etsəniz, sifariş başqa ustaya yönləndiriləcəkdir. Əminsiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Xeyr')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bəli', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _orderService.masterCancelOrder(widget.orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sifariş ləğv edildi.')));
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ləğvetmə zamanı xəta baş verdi.')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aktiv Sifariş')),
      body: StreamBuilder<app_order.Order?>(
        stream: _orderService.getActiveOrderStream(widget.orderId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Sifariş tapılmadı.'));
          }

          final order = snapshot.data!;
          final isArrived = order.status == AppConstants.orderStatusArrived;

          // ✅ ИСПРАВЛЕНИЕ: Используем _userProfileService для получения данных клиента
          final Future<UserProfile?> clientFuture = _userProfileService.getUserProfile(order.customerId);

          return Column(
            children: [
              // -----------------------------------------------------------
              // 1. КАРТА
              // -----------------------------------------------------------
              Expanded(
                child: Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_on, size: 40, color: Colors.red),
                      SizedBox(height: 10),
                      Text(
                        '📍 Klientin yerləşdiyi ünvan',
                        style: TextStyle(color: Colors.grey, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),

              // -----------------------------------------------------------
              // 2. ДЕТАЛИ ЗАКАЗА
              // -----------------------------------------------------------
              Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.all(20.0),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Статус
                      Text(
                        'Status: ${_getStatusText(order.status)}',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getStatusColor(order.status)),
                      ),
                      const Divider(height: 25),

                      // Информация о заказе
                      _buildDetailRow('Kateqoriya', order.category),
                      _buildDetailRow('Problem', order.problemDescription),

                      const SizedBox(height: 15),

                      // Информация о Клиенте
                      FutureBuilder<UserProfile?>(
                        future: clientFuture,
                        builder: (context, clientSnapshot) {
                          if (!clientSnapshot.hasData) return const Text('Klient məlumatları yüklənir...');

                          final client = clientSnapshot.data!;
                          return Column(
                            children: [
                              _buildDetailRow('Klient', client.fullName),
                              _buildDetailRow('Telefon', client.phoneNumber),
                              const SizedBox(height: 15),

                              // Кнопки связи
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => print('Calling ${client.phoneNumber}'),
                                      icon: const Icon(Icons.phone, size: 18),
                                      label: const Text('Zəng'),
                                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => print('Chat with ${client.fullName}'),
                                      icon: const Icon(Icons.message, size: 18),
                                      label: const Text('Mesaj'),
                                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 25),

                      // Кнопки действий
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _cancelOrder,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                side: const BorderSide(color: Colors.red),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              child: const Text('Ləğv Et', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(width: 15),

                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                if (!isArrived) {
                                  _updateStatus(AppConstants.orderStatusArrived);
                                } else {
                                  _updateStatus(AppConstants.orderStatusCompleted);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isArrived ? Colors.green : Colors.orange,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                              child: Text(
                                isArrived ? 'Bitirdim' : 'Çatdım',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case AppConstants.orderStatusAccepted: return 'Sifariş Qəbul Edildi';
      case AppConstants.orderStatusArrived: return 'Siz Ünvandasınız';
      case AppConstants.orderStatusCompleted: return 'Bitdi';
      default: return status;
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case AppConstants.orderStatusAccepted: return Colors.blue;
      case AppConstants.orderStatusArrived: return Colors.orange;
      case AppConstants.orderStatusCompleted: return Colors.green;
      default: return Colors.black;
    }
  }
}