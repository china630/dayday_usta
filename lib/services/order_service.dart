import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:dayday_usta/core/app_constants.dart';
// ✅ Используем префикс, чтобы избежать конфликта имен
import 'package:dayday_usta/models/order.dart' as app_order;

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
        'source': source == app_order.OrderSource.radarSearch ? 'radarSearch' : 'catalogDirect',
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

  /// Срочный заказ из радара / каталога: `createOrder` + радар на сервере.
  /// Повтор заказа: тот же ünvan, kateqoriya, növ; mənbə — kataloq, əgər əvvəl `catalogDirect` + usta id-si var idisə.
  Future<Map<String, dynamic>> repeatOrderFromTemplate({
    required String clientUserId,
    required app_order.Order template,
  }) async {
    final String? targetMasterId = template.source == app_order.OrderSource.catalogDirect &&
            template.masterId != null &&
            template.masterId!.trim().isNotEmpty
        ? template.masterId
        : null;
    final source = targetMasterId != null
        ? app_order.OrderSource.catalogDirect
        : app_order.OrderSource.radarSearch;
    return createOrder(
      clientUserId: clientUserId,
      category: template.category,
      location: template.clientLocation,
      type: template.type,
      source: source,
      scheduledTime: template.type == app_order.OrderType.scheduled ? template.scheduledTime : null,
      targetMasterId: targetMasterId,
    );
  }

  Future<String> initiateEmergencyOrder({
    required String clientUserId,
    required String category,
    required double latitude,
    required double longitude,
  }) async {
    final data = await createOrder(
      clientUserId: clientUserId,
      category: category,
      location: GeoPoint(latitude, longitude),
      type: app_order.OrderType.emergency,
      source: app_order.OrderSource.radarSearch,
    );
    final id = data['orderId'] as String?;
    if (id == null || id.isEmpty) {
      throw Exception('Sifariş ID alınmadı');
    }
    return id;
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
        doc.data(),
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
        doc.data(),
        doc.id
    ))
        .toList());
  }

  Future<void> clientCancelOrder(
    String orderId, {
    String reason = 'client_request',
  }) async {
    try {
      await _functions.httpsCallable('clientCancelOrder').call({
        'orderId': orderId,
        'reason': reason,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('clientCancelOrder: ${e.code} - ${e.message}');
      throw Exception(_formatCallableError(e, fallback: 'Sifarişi ləğv etmək alınmadı'));
    }
  }

  // --------------------------------------------------------------------------
  // 2. MASTER FUNCTIONALITY
  // --------------------------------------------------------------------------

  Stream<List<app_order.Order>> getMasterOrderHistory(String masterId, {bool isActive = false}) {
    final statuses = isActive
        ? <String>[
            AppConstants.orderStatusPending,
            AppConstants.orderStatusAccepted,
            AppConstants.orderStatusArrived,
          ]
        : <String>[
            AppConstants.orderStatusCompleted,
            AppConstants.orderStatusCancelled,
            AppConstants.orderStatusCanceledByMaster,
          ];

    final q1 = _db
        .collection(_ordersCollection)
        .where('masterId', isEqualTo: masterId)
        .where('status', whereIn: statuses)
        .orderBy('createdAt', descending: true);

    final q2 = _db
        .collection(_ordersCollection)
        .where('formerMasterIds', arrayContains: masterId)
        .where('status', whereIn: statuses)
        .orderBy('createdAt', descending: true);

    return Rx.combineLatest2<QuerySnapshot, QuerySnapshot, List<app_order.Order>>(
      q1.snapshots(),
      q2.snapshots(),
      (snap1, snap2) => _mergeMasterOrderSnapshots(snap1, snap2),
    );
  }

  static List<app_order.Order> _mergeMasterOrderSnapshots(
    QuerySnapshot a,
    QuerySnapshot b,
  ) {
    final merged = <String, app_order.Order>{};
    for (final d in a.docs) {
      merged[d.id] = app_order.Order.fromFirestore(
        d.data() as Map<String, dynamic>,
        d.id,
      );
    }
    for (final d in b.docs) {
      merged[d.id] = app_order.Order.fromFirestore(
        d.data() as Map<String, dynamic>,
        d.id,
      );
    }
    final list = merged.values.toList()
      ..sort((x, y) => y.createdAt.compareTo(x.createdAt));
    return list;
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

  Future<void> masterArrived(
    String orderId, {
    required double latitude,
    required double longitude,
  }) async {
    try {
      await _functions.httpsCallable('masterArrived').call({
        'orderId': orderId,
        'latitude': latitude,
        'longitude': longitude,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('masterArrived: ${e.code} - ${e.message}');
      throw Exception(_formatCallableError(e, fallback: 'Yer təsdiqi alınmadı'));
    }
  }

  /// Возвращает [true], если комиссия за этот заказ не списана (стрик «hər 4-cü» за день в Баку).
  Future<bool> masterCompleteOrder(String orderId) async {
    try {
      final result = await _functions.httpsCallable('masterCompleteOrder').call({
        'orderId': orderId,
      });
      final data = result.data;
      if (data is Map) {
        return data['freeCommission'] == true;
      }
      return false;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('masterCompleteOrder: ${e.code} - ${e.message}');
      throw Exception(_formatCallableError(e, fallback: 'Sifarişi bitirmək alınmadı'));
    }
  }

  Future<void> masterCancelOrder(
    String orderId, {
    String reason = 'master_request',
  }) async {
    try {
      await _functions.httpsCallable('masterCancelOrder').call({
        'orderId': orderId,
        'reason': reason,
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('masterCancelOrder: ${e.code} - ${e.message}');
      throw Exception(_formatCallableError(e, fallback: 'Sifarişi ləğv etmək mümkün olmadı'));
    }
  }

  String _formatCallableError(FirebaseFunctionsException e, {required String fallback}) {
    final msg = e.message;
    if (msg != null && msg.trim().isNotEmpty) return msg;
    return fallback;
  }

  // --------------------------------------------------------------------------
  // 3. COMMON / UTILS
  // --------------------------------------------------------------------------

  Stream<app_order.Order?> getActiveOrderStream(String orderId) {
    return _db.collection(_ordersCollection).doc(orderId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return app_order.Order.fromFirestore(
            snapshot.data()!,
            snapshot.id
        );
      }
      return null;
    });
  }

  Future<int> generateMasterTestData() async {
    try {
      final result = await _functions.httpsCallable('generateTestData').call<Map<String, dynamic>>({});
      final count = result.data['count'];
      if (count is int) return count;
      return 0;
    } catch (e) {
      debugPrint('Generation Error: $e');
      throw Exception('Error generating data: $e');
    }
  }
}