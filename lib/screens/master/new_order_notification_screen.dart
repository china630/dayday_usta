import 'package:flutter/material.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/services/order_service.dart';
// import 'package:bolt_usta/screens/master/master_active_order_screen.dart'; // Переход на Активный Заказ

class NewOrderNotificationScreen extends StatefulWidget {
  final app_order.Order order;
  final String masterId; // ID текущего Мастера

  const NewOrderNotificationScreen({required this.order, required this.masterId, super.key});

  @override
  State<NewOrderNotificationScreen> createState() => _NewOrderNotificationScreenState();
}

class _NewOrderNotificationScreenState extends State<NewOrderNotificationScreen> {
  final OrderService _orderService = OrderService();
  bool _isLoading = false;

  // --------------------------------------------------------------------------
  // ЛОГИКА ДЕЙСТВИЙ
  // --------------------------------------------------------------------------

  // Действие: Qəbul Et (Принять)
  Future<void> _acceptOrder() async {
    setState(() => _isLoading = true);
    try {
      // ❗️ Меняет Статус Заказа на 'accepted' и добавляет ID Мастера
      await _orderService.masterAcceptOrder(
        orderId: widget.order.id,
        masterId: widget.masterId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sifariş qəbul edildi.')),
        );
        // Открывает экран “Aktiv Sifariş”
        // Navigator.of(context).pushReplacement(
        //   MaterialPageRoute(builder: (_) => MasterActiveOrderScreen(orderId: widget.order.id)),
        // );
        print('Переход на MasterActiveOrderScreen');
      }
    } catch (e) {
      _showError('Qəbul zamanı xəta: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Действие: İmtina Et (Отменить)
  void _rejectOrder() {
    // В этом случае Мастер просто закрывает уведомление.
    // Заказ остается 'pending', и Cloud Function продолжит поиск других Мастеров.
    // (Имитация: в реальном проекте этот экран просто закрывается)
    Navigator.pop(context);
    print('Sifariş imtina edildi. Axtarış davam edir.');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    // *Имитация расстояния
    const distanceToClient = '2.5 km';

    return Scaffold(
      appBar: AppBar(title: const Text('Yeni Sifariş Bildirişi')), // Уведомление о Новом Заказе
      body: Column(
        children: [
          // -----------------------------------------------------------
          // 1. Placeholder Карты с местоположением Клиента
          // -----------------------------------------------------------
          Expanded(
            child: Container(
              color: Colors.red.shade50,
              alignment: Alignment.center,
              child: const Text(
                '📍 Xəritə: Klientin Lokasiyası', // Карта: Локация Клиента
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ),

          // -----------------------------------------------------------
          // 2. Секция "Sifariş Haqqında" (Информация о Заказе)
          // -----------------------------------------------------------
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('Sifariş Haqqında'), // Информация о Заказе
                _buildDetailRow('Kateqoriya', order.category),
                _buildDetailRow('Təsvir', order.problemDescription), // Краткое описание проблемы
                _buildDetailRow('Məsafə', distanceToClient, icon: Icons.near_me, color: Colors.blue), // Расстояние до Клиента
                const Divider(height: 30),

                // -----------------------------------------------------------
                // 3. Кнопки Действий
                // -----------------------------------------------------------
                Row(
                  children: [
                    // Кнопка Отклонить
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : _rejectOrder,
                        child: const Text('İmtina Et', style: TextStyle(color: Colors.red)), // Отменить
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Кнопка Принять
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isLoading ? null : _acceptOrder,
                        icon: _isLoading ? const SizedBox.shrink() : const Icon(Icons.check, color: Colors.white),
                        label: _isLoading
                            ? const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: CircularProgressIndicator(color: Colors.white))
                            : const Text('Qəbul Et', style: TextStyle(color: Colors.white)), // Принять
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Вспомогательный виджет для заголовков
  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 5),
      child: Text(
        title,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
    );
  }

  // Вспомогательный виджет для отображения деталей
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
}