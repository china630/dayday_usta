import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'dart:io';

class MasterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final String _usersCollection = 'users';
  final String _filtersCollection = 'master_filters';

  // --------------------------------------------------------------------------
  // 1. УПРАВЛЕНИЕ СТАТУСОМ И ПРОФИЛЕМ (CRUD)
  // --------------------------------------------------------------------------

  // ✅ ИСПРАВЛЕНО: toggleMasterStatus обновляет статус в Firestore
  Future<void> toggleMasterStatus(String masterId, bool isAvailable) async {
    // В MasterDashboardScreen используется isAvailable = true для 'free', false для 'busy'
    final newStatus = isAvailable
        ? AppConstants.masterStatusFree
        : AppConstants.masterStatusBusy;

    await _db.collection(_usersCollection).doc(masterId).update({
      'status': newStatus,
    });
  }

  Future<void> updateMasterProfile(MasterProfile profile) async {
    // Обновляем текстовые поля профиля
    await _db.collection(_usersCollection).doc(profile.uid).update({
      'priceList': profile.priceList,
      'achievements': profile.achievements,
    });
  }

  // Обновление фильтров для поиска (Запись в master_filters)
  Future<void> updateMasterSearchFilters(String masterId, List<String> categoryIds, List<String> districtIds) async {
    final batch = _db.batch();

    // 1. Сначала удаляем старые записи из master_filters для этого мастера
    final oldFiltersSnapshot = await _db.collection(_filtersCollection)
        .where('masterId', isEqualTo: masterId)
        .get();

    for (var doc in oldFiltersSnapshot.docs) {
      batch.delete(doc.reference);
    }

    // 2. Создаем новые записи для КАТЕГОРИЙ
    for (var catId in categoryIds) {
      final docRef = _db.collection(_filtersCollection).doc();
      batch.set(docRef, {
        'masterId': masterId,
        'categoryId': catId,
      });
    }

    // 3. Создаем новые записи для РАЙОНОВ
    for (var distId in districtIds) {
      final docRef = _db.collection(_filtersCollection).doc();
      batch.set(docRef, {
        'masterId': masterId,
        'districtId': distId,
      });
    }

    // 4. Также обновляем массивы в основном профиле (для быстрого отображения в UI)
    final masterRef = _db.collection(_usersCollection).doc(masterId);
    batch.update(masterRef, {
      'categories': categoryIds,
      'districts': districtIds,
    });

    await batch.commit();
  }

  Future<MasterProfile?> getProfileData(String masterId) async {
    final doc = await _db.collection(_usersCollection).doc(masterId).get();
    if (doc.exists) {
      // ✅ ИСПОЛЬЗУЕМ: MasterProfile.fromFirestore для получения всех полей
      return MasterProfile.fromFirestore(doc.data() as Map<String, dynamic>);
    }
    return null;
  }

  Future<void> submitVerificationDocs({
    required String masterId,
    required File selfieFile,
    required File docFile,
  }) async {
    final storagePath = 'verification/$masterId';

    // Загрузка в Storage и обновление ссылок в Firestore
    final selfieUrl = await _storage.ref().child('$storagePath/selfie.jpg').putFile(selfieFile).then((task) => task.ref.getDownloadURL());
    final docUrl = await _storage.ref().child('$storagePath/document.jpg').putFile(docFile).then((task) => task.ref.getDownloadURL());

    await _db.collection(_usersCollection).doc(masterId).update({
      'verificationStatus': AppConstants.verificationPending,
      'verificationDocs': {
        'selfieUrl': selfieUrl,
        'docUrl': docUrl,
        'submittedAt': FieldValue.serverTimestamp(),
      },
    });
  }

  // --------------------------------------------------------------------------
  // 2. СЧЕТЧИКИ
  // --------------------------------------------------------------------------

  Future<void> incrementCallsCount(String masterId) async {
    await _db.collection(_usersCollection).doc(masterId).update({
      'callsCount': FieldValue.increment(1),
    });
  }

  Future<void> incrementViewsCount(String masterId) async {
    await _db.collection(_usersCollection).doc(masterId).update({
      'viewsCount': FieldValue.increment(1),
    });
  }

  // --------------------------------------------------------------------------
  // 3. ПОИСК (AND-ЛОГИКА ЧЕРЕЗ ПРОМЕЖУТОЧНУЮ КОЛЛЕКЦИЮ 3NF)
  // --------------------------------------------------------------------------

  // Вспомогательный метод для получения Master IDs по одному фильтру
  Future<Set<String>> _getMastersByFilter(String filterField, String filterValue) async {
    final filtersSnapshot = await _db.collection(_filtersCollection)
        .where(filterField, isEqualTo: filterValue)
        .get();

    return filtersSnapshot.docs
        .map((doc) => (doc.data() as Map<String, dynamic>)['masterId'] as String)
        .toSet();
  }

  // Метод MasterService: searchMasters (Реализация AND-логики через пересечение)
  Future<List<MasterProfile>> searchMasters({
    String? categoryId,
    String? districtId,
    bool onlyFree = false,
  }) async {
    Set<String> masterIds = {};
    List<QueryDocumentSnapshot> mastersDocs = [];

    bool isCategoryFilter = categoryId != null && categoryId.isNotEmpty;
    bool isDistrictFilter = districtId != null && districtId.isNotEmpty;

    // 1. ФИЛЬТРАЦИЯ И ПЕРЕСЕЧЕНИЕ (AND-логика)

    if (isCategoryFilter || isDistrictFilter) {

      // A. Получаем ID по первому фильтру (Категория)
      if (isCategoryFilter) {
        masterIds = await _getMastersByFilter('categoryId', categoryId!);
      }

      // B. Если есть второй фильтр, находим ПЕРЕСЕЧЕНИЕ
      if (isDistrictFilter) {
        final Set<String> districtMasters = await _getMastersByFilter('districtId', districtId!);

        if (isCategoryFilter) {
          masterIds.retainAll(districtMasters);
        } else {
          masterIds = districtMasters;
        }
      }

      if (masterIds.isEmpty && (isCategoryFilter || isDistrictFilter)) {
        return [];
      }
    }

    // 2. ФИНАЛЬНАЯ ВЫБОРКА: Запрос к /users с whereIn

    Query query = _db.collection(_usersCollection)
        .where('role', isEqualTo: AppConstants.dbRoleMaster)
        .where('verificationStatus', isEqualTo: AppConstants.verificationVerified);

    if (masterIds.isNotEmpty) {
      query = query.where(FieldPath.documentId, whereIn: masterIds.toList());
    }

    if (onlyFree) {
      query = query.where('status', isEqualTo: AppConstants.masterStatusFree);
    }

    final snapshot = await query.get();
    mastersDocs = snapshot.docs;


    // 3. СОРТИРОВКА НА СТОРОНЕ КЛИЕНТА (Flutter)

    List<MasterProfile> resultProfiles = mastersDocs
        .map((doc) => MasterProfile.fromFirestore(doc.data() as Map<String, dynamic>))
        .toList();

    // Сортируем по рейтингу (самый высокий рейтинг - первый)
    resultProfiles.sort((a, b) => b.rating.compareTo(a.rating));


    // 4. Возвращаем результаты
    return resultProfiles;
  }
}