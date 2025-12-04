// lib/master_app/accept_order_modal.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:bolt_usta/services/order_service.dart';
// import 'package:bolt_usta/core/app_constants.dart'; // Если нужны константы

// P3.1: Класс для отображения модального окна приема заказа
class AcceptOrderModal extends StatefulWidget {
  final String orderId;
  final String masterId;
  // P3.3: Данные заказа
  final String category;
  final String clientAddress;
  final double distanceKm;

  const AcceptOrderModal({
    super.key,
    required this.orderId,
    required this.masterId,
    required this.category,
    required this.clientAddress,
    required this.distanceKm,
  });

  @override
  State<AcceptOrderModal> createState() => _AcceptOrderModalState();
}

class _AcceptOrderModalState extends State<AcceptOrderModal> {
  final OrderService _orderService = OrderService();
  final int _timeoutSeconds = 10;
  int _timeRemaining = 10;
  Timer? _decisionTimer;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // P3.2: Запуск 10-секундного таймера
    _startTimer();
  }

  void _startTimer() {
    _decisionTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_timeRemaining <= 1) {
        timer.cancel();
        _handleTimeout(); // P3.2: Время вышло
      } else {
        setState(() {
          _timeRemaining--;
        });
      }
    });
  }

  @override
  void dispose() {
    _decisionTimer?.cancel();
    super.dispose();
  }

  // P3.4: Принять заказ
  Future<void> _acceptOrder() async {
    _decisionTimer?.cancel();
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // Вызываем Callable Function acceptOrder
      // Master ID передается неявно через токен аутентификации в Cloud Function
      await _orderService.acceptOrder(orderId: widget.orderId);

      // Заказ успешно принят, закрываем модальное окно
      if (mounted) {
        // Передаем true: заказ принят
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка принятия заказа: ${e.toString()}')),
        );
        setState(() => _isProcessing = false);
        _startTimer(); // Перезапускаем таймер
      }
    }
  }

  // P3.5: Отклонить заказ
  Future<void> _rejectOrder() async {
    _decisionTimer?.cancel();
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      // Вызываем Callable Function rejectOrder
      await _orderService.rejectOrder(orderId: widget.orderId);

      // Заказ успешно отклонен, закрываем модальное окно
      if (mounted) {
        // Передаем false: заказ отклонен
        Navigator.of(context).pop(false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отклонения заказа: ${e.toString()}')),
        );
        setState(() => _isProcessing = false);
        _startTimer(); // Перезапускаем таймер
      }
    }
  }

  // P3.2: Обработка таймаута
  Future<void> _handleTimeout() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // Вызываем Callable Function registerMasterTimeout
    try {
      await _orderService.registerMasterTimeout(
        orderId: widget.orderId,
        masterId: widget.masterId, // Передаем masterId явно
      );
    } catch (e) {
      debugPrint('Error registering timeout: $e');
    }

    // Независимо от успеха, модальное окно закрывается
    if (mounted) {
      // Таймаут считается пропуском/отказом
      Navigator.of(context).pop(false);
    }
  }


  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('НОВЫЙ ЗАКАЗ'),
          // P3.2: Таймер
          Text(
            '$_timeRemaining сек',
            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // P3.3: Карточка заказа
            _buildOrderInfoRow(Icons.build, 'Услуга:', widget.category),
            _buildOrderInfoRow(Icons.location_on, 'Адрес:', widget.clientAddress),
            _buildOrderInfoRow(Icons.alt_route, 'Расстояние:', '${widget.distanceKm.toStringAsFixed(1)} км'),
            const SizedBox(height: 8),
            const Text(
              'ПРИМЕЧАНИЕ: На принятие заказа дается 10 секунд. После таймаута заказ будет передан другому мастеру.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
      actions: [
        if (_isProcessing)
          const Center(child: CircularProgressIndicator())
        else ...[
          // P3.5: Кнопка отклонения
          TextButton(
            onPressed: _rejectOrder,
            child: const Text('ОТКЛОНИТЬ', style: TextStyle(color: Colors.grey)),
          ),
          // P3.4: Кнопка принятия
          ElevatedButton(
            onPressed: _acceptOrder,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
            child: const Text('ПРИНЯТЬ ЗАКАЗ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ],
    );
  }

  Widget _buildOrderInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          Flexible(child: Text(value, textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}