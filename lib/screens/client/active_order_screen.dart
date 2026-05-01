import 'package:flutter/material.dart';
import 'package:dayday_usta/core/app_constants.dart';
import 'package:dayday_usta/models/order.dart' as app_order;
import 'package:dayday_usta/models/master_profile.dart';
import 'package:dayday_usta/services/order_service.dart';
import 'package:dayday_usta/services/master_service.dart';
import 'package:dayday_usta/widgets/pending_client_search_subtitle.dart';
// import 'package:dayday_usta/screens/chat/chat_screen.dart'; // Раскомментируйте, когда добавите чат

class ActiveOrderScreen extends StatefulWidget {
  final String orderId;

  const ActiveOrderScreen({required this.orderId, super.key});

  @override
  State<ActiveOrderScreen> createState() => _ActiveOrderScreenState();
}

class _ActiveOrderScreenState extends State<ActiveOrderScreen> {
  final OrderService _orderService = OrderService();
  final MasterService _masterService = MasterService();

  // Логика отмены заказа клиентом
  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sifarişi Ləğv Et'),
        content: const Text('Sifarişi ləğv etmək istədiyinizə əminsiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Xeyr')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bəli')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _orderService.clientCancelOrder(widget.orderId, reason: 'user_cancel');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sifariş ləğv edildi.')),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      } catch (e) {
        if (mounted) {
          final msg = e is Exception ? e.toString().replaceFirst('Exception: ', '') : 'Ləğvetmə zamanı xəta baş verdi.';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
          if (snapshot.hasError || !snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Sifariş məlumatı tapılmadı.'));
          }

          final order = snapshot.data!;
          final isMasterAssigned = order.masterId != null;
          final isCompleted = order.status == AppConstants.orderStatusCompleted;
          final isCancelled = order.status == AppConstants.orderStatusCancelled ||
              order.status == AppConstants.orderStatusCanceledByMaster;

          // 1. Обработка завершенных/отмененных заказов
          if (isCancelled) {
            return _buildStatusScreen('Sifariş Ləğv Edildi.', Colors.red);
          }

          if (isCompleted) {
            // Здесь можно добавить переход на экран отзыва, если он еще не оставлен
            return _buildStatusScreen('Sifariş Bitirildi. Qiymətləndirin.', Colors.green);
          }

          // 2. Основной интерфейс
          return Column(
            children: [
              // 2.1. Placeholder Карты
              Expanded(
                child: Container(
                  color: Colors.grey.shade200,
                  alignment: Alignment.center,
                  child: const Text(
                    '📍 Xəritə sahəsi (Usta hərəkəti burada izlənilir)',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
              ),

              // 2.2. Панель Деталей Заказа
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status: ${_getStatusText(order.status)}',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _getStatusColor(order.status)),
                    ),
                    const Divider(),

                    _buildDetailRow('Kateqoriya', order.category),
                    _buildDetailRow('Problem', order.problemDescription),

                    const SizedBox(height: 15),

                    // Информация о Мастере
                    if (isMasterAssigned)
                      FutureBuilder<MasterProfile?>(
                        // ✅ ИСПРАВЛЕНИЕ: Запрос к реальному сервису
                        future: _masterService.getProfileData(order.masterId!),
                        builder: (context, masterSnapshot) {
                          if (masterSnapshot.connectionState == ConnectionState.waiting) {
                            return const Center(child: Text('Usta məlumatları yüklənir...'));
                          }
                          if (masterSnapshot.hasData && masterSnapshot.data != null) {
                            final master = masterSnapshot.data!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('Usta', master.fullName),
                                _buildDetailRow('Reytinq', master.rating.toStringAsFixed(1), icon: Icons.star, color: Colors.amber),

                                const SizedBox(height: 10),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton.icon(
                                    onPressed: () {
                                      // Логика открытия чата
                                      // Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(...)));
                                      print('Переход в Чат с мастером: ${master.fullName}');
                                    },
                                    icon: const Icon(Icons.message),
                                    label: const Text('Mesaj Göndər'),
                                  ),
                                ),
                              ],
                            );
                          }
                          return const Center(child: Text('Usta təyin olundu, lakin məlumat tapılmadı.'));
                        },
                      )
                    else
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Usta axtarılır...',
                            style: TextStyle(fontStyle: FontStyle.italic, color: Colors.blue),
                          ),
                          const SizedBox(height: 8),
                          PendingClientSearchSubtitle(
                            order: order,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                          ),
                        ],
                      ),

                    const SizedBox(height: 20),

                    // Кнопка Отмены
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _cancelOrder,
                        icon: const Icon(Icons.close, color: Colors.white),
                        label: const Text('Sifarişi Ləğv Et', style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {IconData? icon, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 5),
          Expanded(
            child: Row(
              children: [
                if (icon != null) Icon(icon, size: 16, color: color ?? Colors.black),
                const SizedBox(width: 4),
                Flexible(child: Text(value)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusScreen(String message, Color color) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 60, color: color),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            child: const Text('Əsas Səhifəyə Qayıt'),
          )
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case AppConstants.orderStatusPending: return 'Usta axtarılır...';
      case AppConstants.orderStatusAccepted: return 'Usta Sifarişi Qəbul Etdi';
      case AppConstants.orderStatusArrived: return 'Usta Çatdı';
      case AppConstants.orderStatusCompleted: return 'Sifariş Bitirildi';
      case AppConstants.orderStatusCancelled: return 'Ləğv Edildi';
      case AppConstants.orderStatusCanceledByMaster: return 'Usta ləğv etdi';
      default: return 'Naməlum Status';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case AppConstants.orderStatusAccepted: return Colors.green;
      case AppConstants.orderStatusArrived: return Colors.orange.shade700;
      case AppConstants.orderStatusPending: return Colors.blue.shade700;
      default: return Colors.black;
    }
  }
}