import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:dayday_usta/core/app_constants.dart';
import 'package:dayday_usta/models/master_profile.dart';
import 'package:dayday_usta/models/order.dart' as app_order;

class AdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(region: 'europe-west3');
  final String _usersCollection = 'users';
  final String _ordersCollection = 'orders';

  // --------------------------------------------------------------------------
  // 1. УПРАВЛЕНИЕ ВЕРИФИКАЦИЕЙ (Eyniləşdirmə)
  // --------------------------------------------------------------------------

  // Метод AdminService: getPendingVerificationMasters
  // Получает поток Мастеров, ожидающих верификацию ('pending')
  Stream<List<MasterProfile>> getPendingVerificationMasters() {
    return _db.collection(_usersCollection)
        .where('role', isEqualTo: AppConstants.dbRoleMaster)
        .where('verificationStatus', isEqualTo: AppConstants.verificationPending)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MasterProfile.fromFirestore(doc.data()))
          .toList();
    });
  }

  // Метод AdminService: adminVerifyMaster
  // Администратор верифицирует Мастера (Status = 'verified') [cite: 51]
  Future<void> adminVerifyMaster(String masterId) async {
    await _functions.httpsCallable('adminSetMasterVerification').call({
      'masterId': masterId,
      'verificationStatus': AppConstants.verificationVerified,
    });
  }

  // Метод AdminService: adminRejectMaster
  // Администратор отклоняет верификацию Мастера (Status = 'rejected') [cite: 51]
  Future<void> adminRejectMaster(String masterId) async {
    await _functions.httpsCallable('adminSetMasterVerification').call({
      'masterId': masterId,
      'verificationStatus': AppConstants.verificationRejected,
    });
  }

  // --------------------------------------------------------------------------
  // 2. СТАТИСТИКА (Gündəlik və Ümumi Statistika)
  // --------------------------------------------------------------------------

  // Метод AdminService: getMasterCount
  // Получает общее количество Мастеров
  Future<int> getMasterCount() async {
    final snapshot = await _db.collection(_usersCollection)
        .where('role', isEqualTo: AppConstants.dbRoleMaster)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  // Метод AdminService: getClientCount
  // Получает общее количество Клиентов
  Future<int> getClientCount() async {
    final snapshot = await _db.collection(_usersCollection)
        .where('role', isEqualTo: AppConstants.dbRoleCustomer)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  // Метод AdminService: getDailyStatistics
  // Получает статистику за последние 24 часа (для 'Gündəlik Statistika')
  Future<Map<String, int>> getDailyStatistics() async {
    final yesterday = DateTime.now().subtract(const Duration(hours: 24));
    final yesterdayTimestamp = Timestamp.fromDate(yesterday);

    // 1. Новые Клиенты и Мастера за 24 часа
    final newUsersSnapshot = await _db.collection(_usersCollection)
        .where('createdAt', isGreaterThanOrEqualTo: yesterdayTimestamp)
        .get();

    int newClients = 0;
    int newMasters = 0;
    for (var doc in newUsersSnapshot.docs) {
      final role = doc.data()['role'];
      if (role == AppConstants.dbRoleCustomer) {
        newClients++; // Количество новых Клиентов
      } else if (role == AppConstants.dbRoleMaster) {
        newMasters++; // Количество новых Мастеров
      }
    }

    // 2. Количество Срочных Заказов за 24 часа
    final newOrdersSnapshot = await _db.collection(_ordersCollection)
        .where('createdAt', isGreaterThanOrEqualTo: yesterdayTimestamp)
        .count()
        .get();

    int newEmergencyOrders = newOrdersSnapshot.count ?? 0; // Количество Срочных Заказов

    return {
      'newClients': newClients,
      'newMasters': newMasters,
      'newEmergencyOrders': newEmergencyOrders,
    };
  }

  // --------------------------------------------------------------------------
  // 3. WEB ADMIN — заказы и аудит (read-only; доступ по Rules: isAdmin)
  // --------------------------------------------------------------------------

  /// Последние заказы для админ-панели (весь `orders` по времени).
  Stream<List<app_order.Order>> watchRecentOrdersForAdmin({int limit = 100}) {
    return _db
        .collection(_ordersCollection)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => app_order.Order.fromFirestore(
                  doc.data(),
                  doc.id,
                ))
            .toList());
  }

  /// События аудита заказа (см. PRD §3.6) — только чтение.
  Stream<List<OrderAuditEventRow>> watchOrderAuditEvents(String orderId, {int limit = 200}) {
    return _db
        .collection(_ordersCollection)
        .doc(orderId)
        .collection('events')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map(OrderAuditEventRow.fromDoc).toList();
    });
  }
}

/// Одна строка аудита для UI админки.
class OrderAuditEventRow {
  final String id;
  final String type;
  final DateTime? timestamp;
  final String? actorId;
  final Map<String, dynamic> details;

  const OrderAuditEventRow({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.actorId,
    required this.details,
  });

  static OrderAuditEventRow fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      return OrderAuditEventRow(
        id: doc.id,
        type: '',
        timestamp: null,
        actorId: null,
        details: const <String, dynamic>{},
      );
    }
    final ts = data['timestamp'];
    DateTime? at;
    if (ts is Timestamp) at = ts.toDate();
    final rawDetails = data['details'];
    final Map<String, dynamic> detailsMap = switch (rawDetails) {
      final Map<String, dynamic> m => m,
      final Map m => Map<String, dynamic>.from(m),
      _ => <String, dynamic>{},
    };
    return OrderAuditEventRow(
      id: doc.id,
      type: data['type'] as String? ?? '',
      timestamp: at,
      actorId: data['actorId'] as String?,
      details: detailsMap,
    );
  }
}