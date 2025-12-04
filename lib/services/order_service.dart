// lib/services/order_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // ✅ НОВЫЙ ИМПОРТ

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'europe-west3',
  );
  final String _ordersCollection = 'orders';


  // ✅ НОВЫЙ ВРЕМЕННЫЙ МЕТОД: Для вызова генерации тестовых данных
  Future<int> generateMasterTestData() async {
    try {
      // Вызываем Callable Function generateTestData
      // NOTE: Это требует, чтобы аутентифицированный пользователь имел права admin!
      final result = await _functions.httpsCallable('generateTestData').call<Map<String, dynamic>>({});

      if (result.data != null && result.data!['count'] is int) {
        return result.data!['count'] as int; // Возвращает количество созданных документов
      }
      throw Exception('Функция не вернула количество созданных документов.');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Generation Error: ${e.code} - ${e.message}');
      throw Exception('Ошибка генерации данных: ${e.message}');
    }
  }


  // --------------------------------------------------------------------------
  // 1. ФУНКЦИОНАЛ КЛИЕНТА (СОЗДАНИЕ ЗАКАЗА)
  // --------------------------------------------------------------------------

  // ✅ НОВЫЙ МЕТОД (P2.4): initiateEmergencyOrder
  // Используется для запуска оптимизированного GeoHash-поиска через Cloud Function.
  Future<String> initiateEmergencyOrder({
    required String clientUserId,
    required String category,
    // Используем LatLng, как в новом UI
    required LatLng clientLocation,
  }) async {
    try {
      // Вызываем Cloud Function onNewEmergencyOrder
      final result = await _functions.httpsCallable('onNewEmergencyOrder').call<Map<String, dynamic>>({
        'clientUserId': clientUserId,
        'category': category,
        'latitude': clientLocation.latitude,
        'longitude': clientLocation.longitude,
      });

      // Бэкенд должен вернуть ID созданного заказа
      if (result.data != null && result.data!['orderId'] is String) {
        return result.data!['orderId'] as String;
      }
      throw Exception('Cloud Function returned no order ID.');
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Cloud Function Error: ${e.code} - ${e.message}');
      throw Exception('Ошибка запуска поиска мастера: ${e.message}');
    } catch (e) {
      rethrow;
    }
  }

  // Метод OrderService: createEmergencyOrder (УСТАРЕВШИЙ МЕТОД)
  // Его функционал заменен initiateEmergencyOrder, но оставлен для совместимости.
  Future<String> createEmergencyOrder({
    required String customerId,
    required String category,
    required String problemDescription,
    required GeoPoint clientLocation,
  }) async {
    final newOrderData = app_order.Order(
      id: '',
      customerId: customerId,
      category: category,
      problemDescription: problemDescription,
      clientLocation: clientLocation,
      createdAt: DateTime.now(),
      status: AppConstants.orderStatusPending,
    ).toFirestore();

    final docRef = await _db.collection(_ordersCollection).add(newOrderData);
    return docRef.id;
  }

  // Метод OrderService: getActiveOrderStream (Оставлен без изменений)
  Stream<app_order.Order?> getActiveOrderStream(String orderId) {
    return _db.collection(_ordersCollection).doc(orderId).snapshots().map((snapshot) {
      if (snapshot.exists) {
        return app_order.Order.fromFirestore(snapshot.data()!, snapshot.id);
      }
      return null;
    });
  }

  // Метод OrderService: clientCancelOrder (Оставлен без изменений)
  Future<void> clientCancelOrder(String orderId) async {
    await _db.collection(_ordersCollection).doc(orderId).update({
      'status': AppConstants.orderStatusCancelled,
    });
  }

  // --------------------------------------------------------------------------
  // 2. ФУНКЦИОНАЛ МАСТЕРА (ОБРАБОТКА ЗАКАЗА)
  // --------------------------------------------------------------------------

  // ✅ НОВЫЙ МЕТОД (P3.4): acceptOrder
  // Чистый wrapper для Callable Function. Используется в новом UI.
  Future<void> acceptOrder({required String orderId}) async {
    try {
      // Мастер ID берется из request.auth.uid в Cloud Function
      await _functions.httpsCallable('acceptOrder').call(<String, dynamic>{
        'orderId': orderId,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Accept Order Error: ${e.code} - ${e.message}');
      throw Exception('Ошибка принятия заказа: ${e.message}');
    }
  }

  // ✅ masterAcceptOrder (УСТАРЕВШИЙ/НЕИСПОЛЬЗУЕМЫЙ МЕТОД - заменен acceptOrder)
  // Оставлен только для того, чтобы показать, что его функционал теперь в acceptOrder
  Future<Map<String, dynamic>> masterAcceptOrder({
    required String orderId,
  }) async {
    try {
      // Используем новый, чистый wrapper
      await acceptOrder(orderId: orderId);
      return {'success': true, 'message': 'Заказ успешно принят.'};
    } catch (e) {
      return {'success': false, 'message': e.toString()};
    }
  }

  // ✅ НОВЫЙ МЕТОД (P3.5): rejectOrder
  // Мастер отклоняет заказ (регистрирует отказ, влияет на "Тройной Отказ")
  Future<void> rejectOrder({required String orderId}) async {
    try {
      // Master ID берется из request.auth.uid
      await _functions.httpsCallable('rejectOrder').call({
        'orderId': orderId,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Reject Order Error: ${e.code} - ${e.message}');
      throw Exception('Ошибка отклонения заказа: ${e.message}');
    }
  }

  // ✅ НОВЫЙ МЕТОД (P3.2): registerMasterTimeout
  // Система регистрирует таймаут (аналогично отклонению, влияет на "Тройной Отказ")
  Future<void> registerMasterTimeout({required String orderId, required String masterId}) async {
    try {
      // NOTE: masterId здесь передается, так как вызов может быть из системы/клиента
      await _functions.httpsCallable('registerMasterTimeout').call({
        'orderId': orderId,
        'masterId': masterId,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Timeout Error: ${e.code} - ${e.message}');
      throw Exception('Ошибка регистрации таймаута: ${e.message}');
    }
  }

  // Метод OrderService: masterArrived (Оставлен без изменений)
  Future<void> masterArrived(String orderId) async {
    await _db.collection(_ordersCollection).doc(orderId).update({
      'status': AppConstants.orderStatusArrived,
    });
  }

  // Метод OrderService: masterCompleteOrder (Оставлен без изменений)
  Future<void> masterCompleteOrder(String orderId) async {
    await _db.collection(_ordersCollection).doc(orderId).update({
      'status': AppConstants.orderStatusCompleted,
    });
  }

  // Метод OrderService: masterCancelOrder (Оставлен без изменений)
  Future<void> masterCancelOrder(String orderId) async {
    await _db.collection(_ordersCollection).doc(orderId).update({
      'status': AppConstants.orderStatusPending,
      'masterId': FieldValue.delete(),
    });
  }
}