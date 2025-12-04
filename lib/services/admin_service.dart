import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';

class AdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
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
          .map((doc) => MasterProfile.fromFirestore(doc.data() as Map<String, dynamic>))
          .toList();
    });
  }

  // Метод AdminService: adminVerifyMaster
  // Администратор верифицирует Мастера (Status = 'verified') [cite: 51]
  Future<void> adminVerifyMaster(String masterId) async {
    await _db.collection(_usersCollection).doc(masterId).update({
      'verificationStatus': AppConstants.verificationVerified,
    });
  }

  // Метод AdminService: adminRejectMaster
  // Администратор отклоняет верификацию Мастера (Status = 'rejected') [cite: 51]
  Future<void> adminRejectMaster(String masterId) async {
    await _db.collection(_usersCollection).doc(masterId).update({
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
}