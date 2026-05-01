// lib/screens/order_search_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:dayday_usta/services/order_service.dart';
import 'package:dayday_usta/core/app_constants.dart';
import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/models/order.dart' as app_order;
import 'order_tracking_screen.dart';
import 'package:dayday_usta/widgets/pending_client_search_subtitle.dart';
import 'package:dayday_usta/services/category_metrics_service.dart';

class OrderSearchScreen extends StatefulWidget {
  final String clientUserId;
  final String category;
  final LatLng clientLocation;

  const OrderSearchScreen({
    super.key,
    required this.clientUserId,
    required this.category,
    required this.clientLocation,
  });

  @override
  State<OrderSearchScreen> createState() => _OrderSearchScreenState();
}

class _OrderSearchScreenState extends State<OrderSearchScreen> {
  final OrderService _orderService = OrderService();
  String? _orderId;
  String? _masterId;
  app_order.Order? _currentOrder;

  // E1.1: Таймер поиска
  int _searchTimeElapsed = 0;
  final int _searchTimeoutSeconds = 60;
  Timer? _searchTimer;
  bool _searchFailed = false;

  StreamSubscription<app_order.Order?>? _orderSubscription;

  @override
  void initState() {
    super.initState();
    _startSearch();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _orderSubscription?.cancel();
    super.dispose();
  }

  // E1.1: Запуск поиска, таймера и подписки
  void _startSearch() async {
    _searchTimer?.cancel();
    _searchTimer = null;
    await _orderSubscription?.cancel();
    _orderSubscription = null;

    setState(() {
      _searchTimeElapsed = 0;
      _searchFailed = false;
      _masterId = null;
      _currentOrder = null;
    });

    // 1. Инициировать заказ на бэкенде
    try {
      final id = await _orderService.initiateEmergencyOrder(
        clientUserId: widget.clientUserId,
        category: widget.category,
        latitude: widget.clientLocation.latitude,
        longitude: widget.clientLocation.longitude,
      );
      if(mounted) {
        setState(() => _orderId = id);
      }

      // 2. Начать подписку на статус заказа в Firestore
      _listenToOrderStatus(id);

      // 3. Запустить 60-секундный таймер
      _searchTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_searchTimeElapsed >= _searchTimeoutSeconds) {
          timer.cancel();
          _handleSearchTimeout(); // E1.2: Время истекло
        } else {
          setState(() {
            _searchTimeElapsed++;
          });
        }
      });

    } catch (e) {
      _searchTimer?.cancel();
      _handleSearchTimeout(error: e.toString());
    }
  }

  // Обработка потока статуса заказа (в т.ч. searchMeta с сервера)
  void _listenToOrderStatus(String orderId) {
    _orderSubscription = _orderService.getActiveOrderStream(orderId).listen((order) {
      if (!mounted || order == null) return;

      setState(() => _currentOrder = order);

      if (order.status == AppConstants.orderStatusAccepted && order.masterId != null) {
        _searchTimer?.cancel();
        _orderSubscription?.cancel();

        _masterId = order.masterId;
        _navigateToTracking();
        return;
      }

      if (order.status == AppConstants.orderStatusCancelled ||
          order.status == AppConstants.orderStatusCanceledByMaster) {
        _searchTimer?.cancel();
        _orderSubscription?.cancel();
        _handleSearchTimeout();
      }
    });
  }

  void _navigateToTracking() {
    if (!mounted || _orderId == null || _masterId == null) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => OrderTrackingScreen(
          orderId: _orderId!,
          masterId: _masterId!,
          clientLocation: widget.clientLocation,
          // TODO: Передать дополнительные детали мастера (например, имя, рейтинг)
        ),
      ),
    );
  }

  // E1.2: Обработка сбоя поиска (если таймаут или ошибка)
  void _handleSearchTimeout({String? error}) {
    if (!mounted) return;

    // TODO: Здесь должен быть вызов Cloud Function для фиксации таймаута на бэкенде
    // _orderService.registerSearchTimeout(_orderId);

    setState(() {
      _searchFailed = true;
    });
  }

  // E1.3 (a): Повторить Поиск
  void _retrySearch() {
    _startSearch();
  }

  // E1.3 (b): Выбрать Мастера Вручную
  void _manualSelection() {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Переход к каталогу мастеров...')),
    );
  }

  // E1.3 (c): Плановый Заказ
  void _scheduleOrder() {
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Переход к оформлению планового заказа...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_searchFailed) {
      // E1.2: Экран Сбоя
      return _buildSearchFailedUI();
    }

    // E1.1: Экран ожидания
    return Scaffold(
      appBar: AppBar(
        title: const Text('Usta axtarılır'),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 150,
                    height: 150,
                    child: CircularProgressIndicator(
                      value: _searchTimeElapsed / _searchTimeoutSeconds,
                      strokeWidth: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: const AlwaysStoppedAnimation<Color>(kPrimaryColor),
                    ),
                  ),
                  Text(
                    '${_searchTimeoutSeconds - _searchTimeElapsed}',
                    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              Text(
                'Təcili usta axtarılır...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey.shade900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              if (_currentOrder != null)
                PendingClientSearchSubtitle(
                  order: _currentOrder!,
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                )
              else
                FutureBuilder<double?>(
                  future: CategoryMetricsService().getAvgFirstAcceptSeconds(widget.category),
                  builder: (context, snap) {
                    final hint = app_order.OrderSearchMeta.avgFirstAcceptHintAz(snap.data);
                    return Text(
                      hint.isEmpty
                          ? 'Yaxınlıqda uyğun usta axtarılır...'
                          : 'Yaxınlıqda uyğun usta axtarılır...\n$hint',
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                      textAlign: TextAlign.center,
                    );
                  },
                ),
              const SizedBox(height: 16),
              Text(
                'Kateqoriya: ${widget.category}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextButton(
                onPressed: () {
                  _searchTimer?.cancel();
                  _orderSubscription?.cancel();
                  Navigator.of(context).pop();
                },
                child: const Text('LƏĞV ET', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // E1.2, E1.3: UI при неудачном поиске
  Widget _buildSearchFailedUI() {
    return Scaffold(
      appBar: AppBar(title: const Text('Поиск не удался')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.sentiment_dissatisfied, size: 80, color: Colors.red),
            const SizedBox(height: 24),
            const Text(
              'К сожалению, сейчас рядом нет свободных мастеров, готовых принять заказ.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),

            // E1.3 (a)
            ElevatedButton(
              onPressed: _retrySearch,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              child: const Text('ПОВТОРИТЬ ПОИСК', style: TextStyle(color: Colors.white)),
            ),
            const SizedBox(height: 12),

            // E1.3 (b)
            TextButton(
              onPressed: _manualSelection,
              child: const Text('ВЫБРАТЬ МАСТЕРА ВРУЧНУЮ'),
            ),
            const SizedBox(height: 8),

            // E1.3 (c)
            TextButton(
              onPressed: _scheduleOrder,
              child: const Text('ОФОРМИТЬ ЗАКАЗ НА ДРУГОЕ ВРЕМЯ'),
            ),
          ],
        ),
      ),
    );
  }
}