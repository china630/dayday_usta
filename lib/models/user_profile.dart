import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String phoneNumber;
  final String role;
  final DateTime createdAt;
  final String name;
  final String surname;
  final String? fcmToken;
  final double balance;
  final double frozenBalance;
  /// Только у клиента: избранные мастера (Firestore `favoriteMasterIds`).
  final List<String> favoriteMasterIds;

  UserProfile({
    required this.uid,
    required this.phoneNumber,
    required this.role,
    required this.createdAt,
    required this.name,
    required this.surname,
    this.fcmToken,
    this.balance = 0.0,       // Дефолт 0
    this.frozenBalance = 0.0, // Дефолт 0
    this.favoriteMasterIds = const [],
  });

  // ✅ Геттер fullName
  String get fullName => '$name $surname';

  // ✅ Геттер availableBalance (Доступные средства)
  double get availableBalance => balance - frozenBalance;

  // ✅ Метод для сохранения в базу
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'phoneNumber': phoneNumber,
      'role': role,
      'createdAt': createdAt,
      'name': name,
      'surname': surname,
      'fcmToken': fcmToken,
      'balance': balance,             // Пишем в БД
      'frozenBalance': frozenBalance, // Пишем в БД
      if (role == 'client') 'favoriteMasterIds': favoriteMasterIds,
    };
  }

  // Алиас для обратной совместимости
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
      // Читаем с защитой типов (int -> double)
      balance: (data['balance'] ?? 0).toDouble(),
      frozenBalance: (data['frozenBalance'] ?? 0).toDouble(),
      favoriteMasterIds: List<String>.from(data['favoriteMasterIds'] ?? []),
    );
  }
}