import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String phoneNumber;
  final String role;
  final DateTime createdAt;
  final String name;
  final String surname;
  final String? fcmToken;

  UserProfile({
    required this.uid,
    required this.phoneNumber,
    required this.role,
    required this.createdAt,
    required this.name,
    required this.surname,
    this.fcmToken,
  });

  // ✅ Геттер fullName (исправляет ошибки в UI)
  String get fullName => '$name $surname';

  // ✅ Метод для сохранения в базу (исправляет ошибки в AuthService)
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'phoneNumber': phoneNumber,
      'role': role,
      'createdAt': createdAt,
      'name': name,
      'surname': surname,
      'fcmToken': fcmToken,
    };
  }

  // Алиас для обратной совместимости (если где-то используется toMap)
  Map<String, dynamic> toMap() => toFirestore();

  factory UserProfile.fromFirestore(Map<String, dynamic> data) {
    return UserProfile(
      uid: data['uid'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      role: data['role'] ?? 'client',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      name: data['name'] ?? '',
      surname: data['surname'] ?? '',
      fcmToken: data['fcmToken'],
    );
  }
}