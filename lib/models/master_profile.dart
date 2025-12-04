import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/user_profile.dart';

// Расширенный профиль для Мастера (Usta)
class MasterProfile extends UserProfile {
  final double rating;
  final String status;
  final String verificationStatus;
  final List<String> categories;
  final List<String> districts;
  final String priceList;
  final String achievements;

  final int viewsCount;
  final int callsCount;
  final int savesCount;

  // ✅ НОВОЕ ПОЛЕ: Счетчик последовательных отказов
  final int consecutiveRejections;

  // КОНСТРУКТОР
  MasterProfile({
    required super.uid,
    required super.phoneNumber,
    required super.createdAt,
    required super.name,
    required super.surname,
    super.fcmToken,
    this.rating = 0.0,
    this.status = AppConstants.masterStatusBusy,
    this.verificationStatus = AppConstants.verificationPending,
    this.categories = const [],
    this.districts = const [],
    this.priceList = '',
    this.achievements = '',
    this.viewsCount = 0,
    this.callsCount = 0,
    this.savesCount = 0,
    // ✅ НОВЫЙ ИМЕНОВАННЫЙ АРГУМЕНТ
    this.consecutiveRejections = 0,
  }) : super(role: AppConstants.dbRoleMaster);

  // 1. ФАБРИЧНЫЙ МЕТОД
  factory MasterProfile.fromFirestore(Map<String, dynamic> data) {
    // В MasterMapData.dart id документа передается как 'uid'
    final user = UserProfile.fromFirestore(data);

    return MasterProfile(
      uid: user.uid,
      phoneNumber: user.phoneNumber,
      createdAt: user.createdAt,
      name: user.name,
      surname: user.surname,
      fcmToken: user.fcmToken,

      rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
      status: data['status'] ?? AppConstants.masterStatusFree,
      verificationStatus: data['verificationStatus'] ?? AppConstants.verificationPending,
      categories: List<String>.from(data['categories'] ?? []),
      districts: List<String>.from(data['districts'] ?? []),
      priceList: data['priceList'] ?? '',
      achievements: data['achievements'] ?? '',
      viewsCount: data['viewsCount'] ?? 0,
      callsCount: data['callsCount'] ?? 0,
      savesCount: data['savesCount'] ?? 0,
      // ✅ ПРИСВОЕНИЕ НОВОГО ПОЛЯ
      consecutiveRejections: data['consecutiveRejections'] ?? 0,
    );
  }

  // 2. TO_FIRESTORE
  @override
  Map<String, dynamic> toFirestore() {
    final base = super.toFirestore();
    return {
      ...base,
      'rating': rating,
      'status': status,
      'verificationStatus': verificationStatus,
      'categories': categories,
      'districts': districts,
      'priceList': priceList,
      'achievements': achievements,
      'viewsCount': viewsCount,
      'callsCount': callsCount,
      'savesCount': savesCount,
      // ✅ ДОБАВЛЕНИЕ НОВОГО ПОЛЯ
      'consecutiveRejections': consecutiveRejections,
    };
  }
}