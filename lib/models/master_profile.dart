import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dayday_usta/models/user_profile.dart';
import 'package:dayday_usta/core/app_constants.dart';

class MasterProfile extends UserProfile {
  final List<String> categories;
  final List<String> districts;
  final String status;
  final String verificationStatus;
  final String achievements; // "Haqqında"
  final String priceList;
  final double rating;
  final int viewsCount;
  final int callsCount;
  final int savesCount;

  MasterProfile({
    required String uid,
    required String phoneNumber,
    required String role,
    required DateTime createdAt,
    required String name,
    required String surname,
    String? fcmToken,
    double balance = 0.0,
    double frozenBalance = 0.0,
    List<String> favoriteMasterIds = const [],

    // Мастер-специфичные поля
    required this.categories,
    required this.districts,
    required this.status,
    required this.verificationStatus,
    this.achievements = '',
    this.priceList = '',
    this.rating = 5.0,
    this.viewsCount = 0,
    this.callsCount = 0,
    this.savesCount = 0,
  }) : super(
    uid: uid,
    phoneNumber: phoneNumber,
    role: role,
    createdAt: createdAt,
    name: name,
    surname: surname,
    fcmToken: fcmToken,
    balance: balance,
    frozenBalance: frozenBalance,
    favoriteMasterIds: favoriteMasterIds,
  );

  // ✅ Исправленный toFirestore
  @override
  Map<String, dynamic> toFirestore() {
    final baseData = super.toFirestore(); // Тут уже будут balance и frozenBalance

    return {
      ...baseData, // Разворачиваем базовые данные
      'categories': categories,
      'districts': districts,
      'status': status,
      'verificationStatus': verificationStatus,
      'achievements': achievements,
      'priceList': priceList,
      'rating': rating,
      'viewsCount': viewsCount,
      'callsCount': callsCount,
      'savesCount': savesCount,
    };
  }

  // Фабрика для создания из Firestore
  factory MasterProfile.fromFirestore(Map<String, dynamic> data) {
    return MasterProfile(
      uid: data['uid'] ?? '',
      phoneNumber: data['phoneNumber'] ?? '',
      role: data['role'] ?? 'master',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      name: data['name'] ?? '',
      surname: data['surname'] ?? '',
      fcmToken: data['fcmToken'],

      // 💰 Читаем баланс
      balance: (data['balance'] ?? 0).toDouble(),
      frozenBalance: (data['frozenBalance'] ?? 0).toDouble(),

      categories: List<String>.from(data['categories'] ?? []),
      districts: List<String>.from(data['districts'] ?? []),
      status: data['status'] ?? AppConstants.masterStatusUnavailable,
      verificationStatus: data['verificationStatus'] ?? AppConstants.verificationPending,
      achievements: data['achievements'] ?? '',
      priceList: data['priceList'] ?? '',
      rating: (data['rating'] ?? 5.0).toDouble(),
      viewsCount: data['viewsCount'] ?? 0,
      callsCount: data['callsCount'] ?? 0,
      savesCount: data['savesCount'] ?? 0,
      favoriteMasterIds: List<String>.from(data['favoriteMasterIds'] ?? []),
    );
  }
}