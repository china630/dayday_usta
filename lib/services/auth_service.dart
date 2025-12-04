import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/user_profile.dart';
import 'package:bolt_usta/models/master_profile.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _usersCollection = 'users';

  // Stream для отслеживания состояния аутентификации
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Получение текущего аутентифицированного пользователя
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  // --------------------------------------------------------------------------
  // 1. УПРАВЛЕНИЕ ПРОФИЛЕМ В FIRESTORE
  // --------------------------------------------------------------------------

  // Получение профиля пользователя из Firestore
  Future<UserProfile?> getCurrentUserProfile() async {
    final user = getCurrentUser();
    if (user == null) {
      return null;
    }

    try {
      final doc = await _db.collection(_usersCollection).doc(user.uid).get();

      if (doc.exists) {
        final data = doc.data()!;

        // 1. ПРОВЕРКА РОЛИ (для входа Администратора)
        // Если роль уже установлена в Firestore, мы считаем профиль полным.
        final role = data['role'] as String?;

        if (role != null) {
          if (role == AppConstants.dbRoleMaster) {
            return MasterProfile.fromFirestore(data);
          } else {
            // Возвращаем базовый профиль для клиента/админа
            return UserProfile.fromFirestore(data);
          }
        }

        // Если роль не установлена, или отсутствуют другие критические поля,
        // то возвращаем null, что направит на RoleSelectionScreen.
        return null;

      }
      return null;
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }

  // Создание нового профиля в Firestore (Customer или Master)
  Future<void> createNewProfile({
    required String uid,
    required String phoneNumber,
    required String role,
    required String name,
    required String surname,
  }) async {
    final String fullName = '$name $surname'.trim();

    if (role == AppConstants.dbRoleCustomer) {

      final userProfile = UserProfile(
        uid: uid,
        phoneNumber: phoneNumber,
        role: role,
        createdAt: DateTime.now(),
        name: name,
        surname: surname,
      );

      await _db.collection(_usersCollection).doc(uid).set(userProfile.toFirestore());

    } else if (role == AppConstants.dbRoleMaster) {

      final masterProfile = MasterProfile(
        uid: uid,
        phoneNumber: phoneNumber,
        createdAt: DateTime.now(),
        name: name,
        surname: surname,
        rating: 0.0,
        callsCount: 0,
        viewsCount: 0,
        status: AppConstants.masterStatusBusy, // 'busy' по умолчанию
        verificationStatus: AppConstants.verificationPending, // 'pending'
        categories: [],
        districts: [],
      );

      await _db.collection(_usersCollection).doc(uid).set(masterProfile.toFirestore());

    } else {
      throw Exception('Invalid role specified: $role');
    }
  }

  // --------------------------------------------------------------------------
  // 2. АУТЕНТИФИКАЦИЯ (РЕАЛЬНАЯ РЕАЛИЗАЦИЯ)
  // --------------------------------------------------------------------------

  // ✅ РЕАЛИЗОВАННЫЙ МЕТОД: verifyPhoneNumber
  Future<void> verifyPhoneNumber(
      String phoneNumber,
      Function(PhoneAuthCredential) verificationCompleted,
      Function(FirebaseAuthException) verificationFailed,
      Function(String, int?) codeSent,
      Function(String) codeAutoRetrievalTimeout
      ) async {

    // ❗️ УБРАН print() - ДОБАВЛЕН РЕАЛЬНЫЙ ВЫЗОВ
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
    );
  }

  // РЕАЛИЗОВАННЫЙ МЕТОД: signInWithCredential
  Future<UserCredential> signInWithCredential(PhoneAuthCredential credential) async {
    return await _auth.signInWithCredential(credential);
  }

  // Выход из системы
  Future<void> signOut() async {
    await _auth.signOut();
  }
}