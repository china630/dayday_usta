// lib/screens/order_tracking_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/models/master_profile.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String masterId;
  final LatLng clientLocation;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    required this.masterId,
    required this.clientLocation,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OrderService _orderService = OrderService();

  // P3.7: Для локации мастера
  StreamSubscription? _masterLocationSubscription;
  LatLng? _masterLocation;

  // P3.6: Для статуса заказа
  StreamSubscription<app_order.Order?>? _orderStatusSubscription;
  String _currentStatus = AppConstants.orderStatusAccepted;

  // P3.8: Данные мастера
  MasterProfile? _masterProfile;

  GoogleMapController? _mapController;

  final double _defaultMasterRating = 5.0;
  final String _defaultMasterName = 'Мастер Загружается...';
  // TODO: Реализация расчета ETA (Estimated Time of Arrival) требует использования API Google Maps Directions.
  final String _defaultETA = 'В пути';

  @override
  void initState() {
    super.initState();
    _fetchMasterData();
    _subscribeToMasterLocation(); // P3.7
    _subscribeToOrderStatus(); // P3.6, P3.11
  }

  @override
  void dispose() {
    _masterLocationSubscription?.cancel();
    _orderStatusSubscription?.cancel();
    super.dispose();
  }

  // Хелпер для получения профиля мастера
  Future<void> _fetchMasterData() async {
    try {
      final doc = await _firestore.collection('users').doc(widget.masterId).get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            // NOTE: Предполагается, что MasterProfile.fromFirestore обрабатывает GeoPoint (lastLocation)
            // Мы передаем данные целиком, включая uid
            _masterProfile = MasterProfile.fromFirestore({...doc.data()!, 'uid': doc.id});
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching master profile: $e');
    }
  }

  // P3.7: Подписка на живую локацию мастера
  void _subscribeToMasterLocation() {
    _masterLocationSubscription = _firestore
        .collection('users')
        .doc(widget.masterId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;

      final data = snapshot.data();
      final GeoPoint? geoPoint = data?['lastLocation'] as GeoPoint?;

      if (geoPoint != null) {
        setState(() {
          _masterLocation = LatLng(geoPoint.latitude, geoPoint.longitude);
          // _updateCameraBounds(); // Можно закомментировать, чтобы карта не прыгала
        });
      }
    });
  }

  // P3.6, P3.11: Подписка на статус заказа
  void _subscribeToOrderStatus() {
    _orderStatusSubscription = _orderService.getActiveOrderStream(widget.orderId).listen((order) {
      if (order == null || !mounted) return;

      if (order.status != _currentStatus) {
        setState(() {
          _currentStatus = order.status;
        });

        // P3.11: Логика открытия окна оценки
        if (order.status == AppConstants.orderStatusCompleted) {
          _orderStatusSubscription?.cancel();
          _showRatingDialog();
        }

        // Оповещение о прибытии
        if (order.status == AppConstants.orderStatusArrived) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Мастер прибыл на место!')),
          );
        }
      }
    });
  }

  // P3.11: Окно оценки работы мастера
  void _showRatingDialog() {
    // Используем Future.delayed, чтобы убедиться, что экран прогрузился
    Future.delayed(Duration.zero, () {
      showDialog(
        context: context,
        barrierDismissible: false, // Обязательно для оценки
        builder: (BuildContext context) {
          double _selectedRating = 5.0; // Значение по умолчанию
          String _comment = '';

          return AlertDialog(
            title: const Text('Оцените работу мастера'),
            content: StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Как вы оцените ${_masterProfile?.fullName ?? "мастера"}?'),
                    const SizedBox(height: 16),
                    // Простой виджет выбора звезд
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return IconButton(
                          icon: Icon(
                            index < _selectedRating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedRating = index + 1.0;
                            });
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Комментарий (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      onChanged: (text) => _comment = text,
                    ),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  // TODO: Вызов Cloud Function onNewReview(_selectedRating, _comment)
                  // Используем заглушку
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Отправлена оценка: $_selectedRating')),
                  );
                  Navigator.of(context).pop();
                  // Закрыть экран отслеживания и перейти на главный
                  Navigator.of(context).pop();
                },
                child: const Text('ОЦЕНИТЬ И ЗАВЕРШИТЬ'),
              ),
            ],
          );
        },
      );
    });
  }

  // P3.6: Метод для генерации маркеров
  Set<Marker> _getMarkers() {
    final markers = <Marker>{};

    // Маркер клиента
    markers.add(
      Marker(
        markerId: const MarkerId('clientLocation'),
        position: widget.clientLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'Вы здесь (Клиент)'),
      ),
    );

    // Маркер мастера (P3.7)
    if (_masterLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('masterLocation'),
          position: _masterLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: InfoWindow(
            title: _masterProfile?.fullName ?? _defaultMasterName,
            snippet: 'Статус: ${_currentStatus == AppConstants.orderStatusArrived ? "Прибыл" : "В пути"}',
          ),
        ),
      );
    }
    return markers;
  }

  // P3.6: Начальная позиция карты
  CameraPosition _getCameraPosition() {
    // Центрируем на клиенте с зумом 14
    return CameraPosition(target: widget.clientLocation, zoom: 14);
  }


  @override
  Widget build(BuildContext context) {
    final masterName = _masterProfile?.fullName ?? _defaultMasterName;
    final rating = _masterProfile?.rating ?? _defaultMasterRating;
    final etaText = _currentStatus == AppConstants.orderStatusAccepted ? 'В пути' :
    _currentStatus == AppConstants.orderStatusArrived ? 'Прибыл!' :
    _defaultETA;

    return Scaffold(
      appBar: AppBar(
        title: Text('Отслеживание заказа (#${widget.orderId.substring(0, 4)}...)'),
        backgroundColor: Colors.red,
        actions: [
          // Кнопка отмены заказа клиентом
          TextButton(
            onPressed: () {
              // TODO: Добавить диалог подтверждения отмены
              _orderService.clientCancelOrder(widget.orderId);
              Navigator.of(context).pop();
            },
            child: const Text('ОТМЕНИТЬ ЗАКАЗ', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        children: [
          // P3.6, P3.7: Google Map
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: _getCameraPosition(),
            onMapCreated: (controller) {
              _mapController = controller;
              // Если есть и клиент, и мастер, можно обновить границы карты
              if (_masterLocation != null) {
                // _updateCameraBounds();
              }
            },
            markers: _getMarkers(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
          ),

          // Карточка статуса (P3.8, P3.9)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildMasterInfoCard(masterName, rating, etaText),
          ),
        ],
      ),
    );
  }

  // P3.8, P3.9: Нижняя карточка с информацией о мастере
  Widget _buildMasterInfoCard(String masterName, double rating, String eta) {
    return Card(
      elevation: 8,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // P3.8: Статус и ETA
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(masterName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(rating.toStringAsFixed(1), style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Статус:', style: TextStyle(color: Colors.grey)),
                    Text(
                      eta,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: _currentStatus == AppConstants.orderStatusArrived ? Colors.green.shade700 : Colors.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),

            // P3.9: Кнопки связи
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionButton(Icons.phone, 'Позвонить', () {
                  // TODO: Логика звонка (url_launcher)
                }),
                _buildActionButton(Icons.chat_bubble, 'Чат', () {
                  // TODO: Логика чата (Переход на экран чата)
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label, VoidCallback onPressed) {
    return TextButton.icon(
      icon: Icon(icon, color: Colors.blue.shade700),
      label: Text(label, style: TextStyle(color: Colors.blue.shade700)),
      onPressed: onPressed,
    );
  }
}