import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/models/user_profile.dart'; // Для получения данных Клиента
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/services/auth_service.dart'; // Используем для получения данных Клиента

class MasterActiveOrderScreen extends StatefulWidget {
  final String orderId;

  const MasterActiveOrderScreen({required this.orderId, super.key});

  @override
  State<MasterActiveOrderScreen> createState() => _MasterActiveOrderScreenState();
}

class _MasterActiveOrderScreenState extends State<MasterActiveOrderScreen> {
  final OrderService _orderService = OrderService();
  final AuthService _authService = AuthService(); // Используем для получения профиля Клиента

  // Логика обновления статуса Мастером
  Future<void> _updateStatus(String newStatus) async {
    try {
      if (newStatus == AppConstants.orderStatusArrived) {
        // 1. Статус "Çatdım" (Прибыл)
        await _orderService.masterArrived(widget.orderId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status yeniləndi: Çatdım.')),
        );
      } else if (newStatus == AppConstants.orderStatusCompleted) {
        // 2. Статус "Bitirdim" (Завершил)
        await _orderService.masterCompleteOrder(widget.orderId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sifariş uğurla bitirildi.')),
        );
        // Возвращение на MasterDashboard
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      setState(() {}); // Принудительное обновление UI для перерисовки кнопки
    } catch (e) {
      print('Ошибка обновления статуса: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xəta baş verdi. Status dəyişmədi.')),
      );
    }
  }

  // Логика отмены заказа Мастером
  Future<void> _cancelOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sifarişi Ləğv Et'), // Отменить заказ
        content: const Text('Ləğv etsəniz, sifariş başqa ustaya yönləndiriləcəkdir. Əminsiniz?'), // Если отмените, заказ будет передан другому мастеру.
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Xeyr')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Bəli')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // ❗️ Удаляет ID Мастера и меняет Статус Заказа на 'pending'
        await _orderService.masterCancelOrder(widget.orderId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sifariş ləğv edildi və yenidən axtarışa verildi.')),
          );
          // Возвращение на Master Dashboard
          Navigator.of(context).pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Ləğvetmə zamanı xəta baş verdi.')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Aktiv Sifariş')), // Активный Заказ
      body: StreamBuilder<app_order.Order?>(
        stream: _orderService.getActiveOrderStream(widget.orderId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Sifariş tapılmadı.')); // Заказ не найден
          }

          final order = snapshot.data!;
          final isArrived = order.status == AppConstants.orderStatusArrived;

          // *Имитация получения данных Клиента (в реальном проекте - через getProfileData)
          final Future<UserProfile?> clientFuture = _authService.getCurrentProfileById(order.customerId);

          return Column(
            children: [
              // -----------------------------------------------------------
              // 1. Placeholder Карты и Информации о Гео
              // -----------------------------------------------------------
              Expanded(
                child: Container(
                  color: Colors.blue.shade50,
                  alignment: Alignment.center,
                  child: const Text(
                    '📍 Xəritə: Klientin yerləşdiyi ünvan', // Карта: адрес клиента
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
              ),

              // -----------------------------------------------------------
              // 2. Панель Управления и Информация о Клиенте
              // -----------------------------------------------------------
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Информация о Заказе
                    _buildDetailRow('Kateqoriya', order.category),
                    _buildDetailRow('Problem', order.problemDescription),
                    const Divider(),

                    // Информация о Клиенте
                    FutureBuilder<UserProfile?>(
                      future: clientFuture,
                      builder: (context, clientSnapshot) {
                        if (!clientSnapshot.hasData || clientSnapshot.data == null) {
                          return const Text('Klient məlumatları yüklənir...');
                        }
                        final client = clientSnapshot.data!;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Используем getter fullName, который склеивает name + surname
                            _buildDetailRow('Klient', client.fullName),
                            _buildDetailRow('Telefon', client.phoneNumber),
                            const SizedBox(height: 10),
                            // Кнопки Связи
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildContactButton(Icons.phone, 'Zəng Et', () => print('Calling ${client.phoneNumber}')),
                                _buildContactButton(Icons.message, 'Mesaj Göndər', () => print('Opening chat with ${client.fullName}')),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                    const Divider(),

                    // Кнопки Управления Статусом
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Кнопка Отмены
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _cancelOrder,
                            child: const Text('Ləğv Et'), // Отменить Заказ
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Кнопка "Çatdım" или "Bitirdim"
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              if (!isArrived) {
                                _updateStatus(AppConstants.orderStatusArrived); // Çatdım
                              } else {
                                _updateStatus(AppConstants.orderStatusCompleted); // Bitirdim
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isArrived ? Colors.green.shade700 : Colors.orange.shade700,
                              padding: const EdgeInsets.symmetric(vertical: 15),
                            ),
                            child: Text(
                              isArrived ? 'Bitirdim' : 'Çatdım', // Завершил / Прибыл
                              style: const TextStyle(color: Colors.white, fontSize: 16),
                            ),
                          ),
                        ),
                      ],
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

  // Вспомогательный виджет для отображения деталей
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  // Вспомогательный виджет для кнопок связи
  Widget _buildContactButton(IconData icon, String label, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4.0),
        child: TextButton.icon(
          onPressed: onTap,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }
}

// ❗️ Добавляем заглушку метода для AuthService для компиляции
extension AuthServiceProfileFetch on AuthService {
  Future<UserProfile?> getCurrentProfileById(String userId) async {
    // Имитация получения данных клиента
    await Future.delayed(const Duration(milliseconds: 200));

    // ✅ ИСПРАВЛЕНО: Передаем name и surname отдельно, и используем правильную константу роли
    return UserProfile(
      uid: userId,
      phoneNumber: '99470xxxxxx',
      createdAt: DateTime.now(),
      name: 'Fərid',          // Имя отдельно
      surname: 'Həsənov',     // Фамилия отдельно
      role: AppConstants.dbRoleCustomer, // Правильная константа (dbRoleCustomer)
    );
  }
}