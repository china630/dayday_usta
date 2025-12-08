import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/models/user_profile.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/services/user_profile_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
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

  // Регистрация Клиента
  Future<void> registerClient({
    required String uid,
    required String phoneNumber,
    required String name,
    required String surname,
  }) async {
    final userProfile = UserProfile(
      uid: uid,
      phoneNumber: phoneNumber,
      role: 'client',
      createdAt: DateTime.now(),
      name: name,
      surname: surname,
    );

    await _db.collection('users').doc(uid).set(userProfile.toFirestore());
  }

  // Регистрация Мастера
  Future<void> registerMaster({
    required String uid,
    required String phoneNumber,
    required String name,
    required String surname,
    required List<String> categories,
    required List<String> districts,
  }) async {
    // ✅ ИСПРАВЛЕНО: Добавлен параметр 'role'
    final masterProfile = MasterProfile(
      uid: uid,
      phoneNumber: phoneNumber,
      role: 'master', // <--- ВОТ ЗДЕСЬ ИСПРАВЛЕНИЕ
      createdAt: DateTime.now(),
      name: name,
      surname: surname,
      categories: categories,
      districts: districts,
      status: AppConstants.masterStatusUnavailable, // Изначально недоступен
      verificationStatus: AppConstants.verificationPending, // Ждет верификации
    );

    // Сохраняем профиль
    await _db.collection('users').doc(uid).set(masterProfile.toFirestore());

    // Обновляем фильтры поиска (3NF)
    // Внимание: Этот код дублируется в MasterService, лучше бы вынести, но пока оставим здесь
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
}