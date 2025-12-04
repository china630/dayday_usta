// lib/services/user_profile_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/core/app_constants.dart';

class UserProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _usersCollection = 'users';

  // Получение потока профиля мастера для отслеживания статуса и счетчика
  Stream<MasterProfile> getMasterProfileStream(String masterId) {
    return _db.collection(_usersCollection).doc(masterId).snapshots().map((snapshot) {
      if (snapshot.exists && snapshot.data() != null) {
        return MasterProfile.fromFirestore({...snapshot.data()!, 'uid': snapshot.id});
      }
      // Возвращаем пустой профиль или бросаем ошибку, если профиль не найден
      throw Exception("Master profile not found.");
    });
  }

  // A1.3: Ручная смена статуса мастера (например, с 'unavailable' на 'free')
  Future<void> updateMasterStatus(String masterId, String newStatus) async {
    // Проверка на допустимые статусы (free, busy, unavailable)
    if ([AppConstants.masterStatusFree, AppConstants.masterStatusBusy].contains(newStatus)) {
      await _db.collection(_usersCollection).doc(masterId).update({
        'status': newStatus,
      });
    } else {
      throw Exception("Invalid status update attempt.");
    }
  }

  // Обновление местоположения (для симуляции, если бы оно не обновлялось через Cloud Function)
  Future<void> updateMasterLocation(String masterId, double lat, double lon) async {
    await _db.collection(_usersCollection).doc(masterId).update({
      'lastLocation': GeoPoint(lat, lon),
    });
  }
}