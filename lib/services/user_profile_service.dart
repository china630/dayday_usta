import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dayday_usta/models/user_profile.dart';
import 'package:dayday_usta/models/master_profile.dart'; // ✅ Импортируем MasterProfile

class UserProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _collection = 'users';

  Future<void> saveUserProfile(UserProfile userProfile) async {
    await _db.collection(_collection).doc(userProfile.uid).set(userProfile.toMap());
  }

  Future<UserProfile?> getUserProfile(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection(_collection).doc(uid).get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;

        // Добавляем UID в карту данных, если его там нет (для надежности)
        data['uid'] = uid;

        final role = data['role'];

        // ✅ ИСПРАВЛЕНИЕ: Если роль "master", создаем MasterProfile
        if (role == 'master') {
          return MasterProfile.fromFirestore(data);
        }
        // Иначе создаем обычный UserProfile
        else {
          return UserProfile.fromFirestore(data);
        }
      }
      return null;
    } catch (e) {
      print('Error fetching user profile: $e');
      return null;
    }
  }
}