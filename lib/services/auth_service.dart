import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ Добавил для уведомлений

import 'package:dayday_usta/models/user_profile.dart';
import 'package:dayday_usta/models/master_profile.dart';
import 'package:dayday_usta/core/app_constants.dart';
import 'package:dayday_usta/services/user_profile_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseMessaging _fcm = FirebaseMessaging.instance; // ✅ Инстанс FCM
  final UserProfileService _userProfileService = UserProfileService();

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? getCurrentUser() {
    return _auth.currentUser;
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<UserProfile?> getCurrentUserProfile() async {
    final user = _auth.currentUser;
    if (user != null) {
      return await _userProfileService.getUserProfile(user.uid);
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // РЕГИСТРАЦИЯ КЛИЕНТА
  // ---------------------------------------------------------------------------
  Future<void> registerClient({
    required String uid,
    required String phoneNumber,
    required String name,
    required String surname,
  }) async {
    // ✅ Получаем токен для уведомлений сразу при регистрации
    String? fcmToken = await _fcm.getToken();

    final userProfile = UserProfile(
      uid: uid,
      phoneNumber: phoneNumber,
      role: 'client',
      createdAt: DateTime.now(),
      name: name,
      surname: surname,
      fcmToken: fcmToken, // ✅ Сохраняем токен

      // 💰 Инициализируем нулями. Бонус (20 AZN) начислит сервер.
      balance: 0.0,
      frozenBalance: 0.0,
    );

    await _db.collection('users').doc(uid).set(userProfile.toFirestore());
  }

  // ---------------------------------------------------------------------------
  // РЕГИСТРАЦИЯ МАСТЕРА
  // ---------------------------------------------------------------------------
  Future<void> registerMaster({
    required String uid,
    required String phoneNumber,
    required String name,
    required String surname,
    required List<String> categories,
    required List<String> districts,
  }) async {
    // ✅ Получаем токен для уведомлений
    String? fcmToken = await _fcm.getToken();

    final masterProfile = MasterProfile(
      uid: uid,
      phoneNumber: phoneNumber,
      role: 'master',
      createdAt: DateTime.now(),
      name: name,
      surname: surname,
      fcmToken: fcmToken, // ✅ Сохраняем токен

      // 💰 Инициализируем нулями.
      balance: 0.0,
      frozenBalance: 0.0,

      categories: categories,
      districts: districts,
      status: AppConstants.masterStatusUnavailable,
      verificationStatus: AppConstants.verificationPending,

      // Дефолтные значения для статистики (чтобы не было null в UI)
      achievements: '',
      priceList: '',
      rating: 5.0,
      viewsCount: 0,
      callsCount: 0,
      savesCount: 0,
    );

    // 1. Сохраняем профиль мастера
    await _db.collection('users').doc(uid).set(masterProfile.toFirestore());

    // 2. Обновляем фильтры поиска (Твой код с Batch Write)
    final batch = _db.batch();

    // Категории
    for (var cat in categories) {
      final docRef = _db.collection('master_filters').doc();
      batch.set(docRef, {'masterId': uid, 'categoryId': cat});
    }
    // Районы
    for (var dist in districts) {
      final docRef = _db.collection('master_filters').doc();
      batch.set(docRef, {'masterId': uid, 'districtId': dist});
    }

    await batch.commit();
  }

  // Полезный метод для обновления токена при входе (если юзер сменил телефон)
  Future<void> updateUserToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      String? token = await _fcm.getToken();
      if (token != null) {
        await _db.collection('users').doc(user.uid).update({
          'fcmToken': token,
        });
      }
    }
  }
}