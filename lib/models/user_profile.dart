import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/core/app_constants.dart';

// Базовый профиль пользователя для Firestore
class UserProfile {
  final String uid;
  final String phoneNumber;
  final String role; // Müştəri, Usta, Admin
  final DateTime createdAt;
  final String name; // Имя (Обязательное)
  final String surname; // Фамилия (Обязательное)
  final String? fcmToken; // Токен для уведомлений

  String get fullName => '$name $surname'.trim(); // Вычисляемый геттер

  // КОНСТРУКТОР: role является обязательным ИМЕНОВАННЫМ аргументом.
  UserProfile({
    required this.uid,
    required this.phoneNumber,
    required String role,
    required this.createdAt,
    required this.name,
    required this.surname,
    this.fcmToken,
  }) :  this.role = role;

  // 1. ФАБРИЧНЫЙ МЕТОД
  factory UserProfile.fromFirestore(Map<String, dynamic> data) {
    Timestamp ts = data['createdAt'] ?? Timestamp.now();

    return UserProfile(
      uid: data['uid'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      role: data['role'] ?? AppConstants.dbRoleCustomer,
      createdAt: ts.toDate(),
      name: data['name'] ?? '',
      surname: data['surname'] ?? '',
      fcmToken: data['fcmToken'],
    );
  }

  // 2. TO_FIRESTORE
  @override
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'phoneNumber': phoneNumber,
      'role': role,
      'createdAt': Timestamp.fromDate(createdAt),
      'name': name,
      'surname': surname,
      'fcmToken': fcmToken,
    };
  }
}