import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_constants.dart';
// ✅ Используем префикс, чтобы избежать конфликта имен
import 'package:bolt_usta/models/order.dart' as app_order;

class OrderService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'europe-west3',
  );
  final String _ordersCollection = 'orders';

  // --------------------------------------------------------------------------
  // 1. CUSTOMER FUNCTIONALITY
  // --------------------------------------------------------------------------

  Future<bool> hasActiveOrderInCategory(String customerId, String category) async {
    try {
      final snapshot = await _db.collection(_ordersCollection)
          .where('customerId', isEqualTo: customerId)
          .where('category', isEqualTo: category)
          .where('status', whereIn: [
        AppConstants.orderStatusPending,
        AppConstants.orderStatusAccepted,
        AppConstants.orderStatusArrived,
      ])
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint("Error checking active orders: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>> createOrder({
    required String clientUserId,
    required String category,
    required GeoPoint location,
    required app_order.OrderType type,
    required app_order.OrderSource source,
    DateTime? scheduledTime,
    String? targetMasterId,
  }) async {
    try {
      final callable = _functions.httpsCallable('createOrder');
      final result = await callable.call({
        'clientUserId': clientUserId,
        'category': category,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'type': type == app_order.OrderType.emergency ? 'emergency' : 'scheduled',
        'source': source == app_order.OrderSource.boltSearch ? 'boltSearch' : 'catalogDirect',
        'scheduledTime': scheduledTime?.toIso8601String(),
        'targetMasterId': targetMasterId,
      });
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Cloud Function Error: ${e.code} - ${e.message}');
      throw Exception('Sifariş yaradılarkən xəta: ${e.message}');
    } catch (e) {
      debugPrint('General Error creating order: $e');
      rethrow;
    }
  }

  Stream<List<app_order.Order>> getClientActiveOrdersStream(String clientId) {
    return _db.collection(_ordersCollection)
        .where('customerId', isEqualTo: clientId)
        .where('status', whereIn: [
      AppConstants.orderStatusPending,
      AppConstants.orderStatusAccepted,
      AppConstants.orderStatusArrived,
    ])
        .snapshots()
        .map((snapshot) => snapshot.docs
    // ✅ ИСПРАВЛЕНО: Приведение типа к Map<String, dynamic>
        .map((doc) => app_order.Order.fromFirestore(
        doc.data() as Map<String, dynamic>,
        doc.id
    ))
        .toList());
  }

  Stream<List<app_order.Order>> getClientOrderHistory(String customerId) {
    return _db.collection(_ordersCollection)
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
    // ✅ ИСПРАВЛЕНО: Приведение типа к Map<String, dynamic>
        .map((doc) => app_order.Order.fromFirestore(
        doc.data() as Map<String, dynamic>,
        doc.id
    ))
        .toList());
  }

  Future<void> clientCancelOrder(String orderId) async {
    await _db.collection(_ordersCollection).doc(orderId).update({
      'status': AppConstants.orderStatusCancelled,
    });
  }

  // --------------------------------------------------------------------------
  // 2. MASTER FUNCTIONALITY
  // --------------------------------------------------------------------------

  Stream<List<app_order.Order>> getMasterOrderHistory(String masterId, {bool isActive = false}) {
    Query query = _db.collection(_ordersCollection).where('masterId', isEqualTo: masterId);

    if (isActive) {
      query = query.where('status', whereIn: [
        AppConstants.orderStatusPending,
        AppConstants.orderStatusAccepted,
        AppConstants.orderStatusArrived
      ]);
    } else {
      query = query.where('status', whereIn: [
        AppConstants.orderStatusCompleted,
        AppConstants.orderStatusCancelled
      ]);
    }

    return query.orderBy('createdAt', descending: true).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => app_order.Order.fromFirestore(
          doc.data() as Map<String, dynamic>, // ✅ ИСПРАВЛЕНО
          doc.id
      )).toList();
    });
  }

  Future<void> acceptOrder({required String orderId}) async {
    try {
      await _functions.httpsCallable('acceptOrder').call({'orderId': orderId});
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Accept Order Error: ${e.code} - ${e.message}');
      throw Exception('Sifarişi qəbul edərkən xəta: ${e.message}');
    }
  }

  Future<void> rejectOrder({required String orderId}) async {
    try {
      await _functions.httpsCallable('rejectOrder').call({'orderId': orderId});
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Reject Order Error: ${e.code} - ${e.message}');
      throw Exception('Sifarişdən imtina edərkən xəta: ${e.message}');
    }
  }

  Future<void> registerMasterTimeout({required String orderId, required String masterId}) async {
    try {
      await _functions.httpsCallable('registerMasterTimeout').call({
        'orderId': orderId,
        'masterId': masterId,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('Timeout Error: ${e.code} - ${e.message}');
    }
  }

  Future<void> masterArrived(String orderId) async {
    await _db.collection(_ordersCollection).doc(orderId).update({
      'status': AppConstants.orderStatusArrived,
    });
  }

  Future<void> masterCompleteOrder(String orderId) async {
    await _db.collection(_ordersCollection).doc(orderId).update({
      'status': AppConstants.orderStatusCompleted,
    });
  }

  Future<void> masterCancelOrder(String orderId) async {
    try {
      await _db.collection(_ordersCollection).doc(orderId).update({
        'status': AppConstants.orderStatusCancelled,
      });
    } catch (e) {
      debugPrint('Error master canceling order: $e');
      throw Exception('Sifarişi ləğv etmək mümkün olmadı: $e');
    }
  }

  // --------------------------------------------------------------------------
  // 3. COMMON / UTILS
  // --------------------------------------------------------------------------

  Stream<app_order.Order?> getActiveOrderStream(String orderId) {
    return _db.collection(_ordersCollection).doc(orderId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        // ✅ ИСПРАВЛЕНО: Приведение типа к Map<String, dynamic>
        return app_order.Order.fromFirestore(
            snapshot.data() as Map<String, dynamic>,
            snapshot.id
        );
      }
      return null;
    });
  }

  Future<int> generateMasterTestData() async {
    try {
      final result = await _functions.httpsCallable('generateTestData').call<Map<String, dynamic>>({});
      if (result.data != null && result.data!['count'] is int) {
        return result.data!['count'] as int;
      }
      return 0;
    } catch (e) {
      debugPrint('Generation Error: $e');
      throw Exception('Error generating data: $e');
    }
  }
}