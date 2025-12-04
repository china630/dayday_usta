import 'package:cloud_firestore/cloud_firestore.dart';

class DataManagementService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _usersCollection = 'users';

  // -----------------------------------------------------------
  // ОБЩИЕ МЕТОДЫ ДЛЯ СБОРА ДАННЫХ
  // -----------------------------------------------------------

  // Получить стрим всех активных элементов (Категории или Районы)
  Stream<List<Map<String, dynamic>>> getActiveItemsStream(String collectionName) {
    return _db.collection(collectionName)
        .where('isActive', isEqualTo: true)
        .orderBy('name')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => {
        'id': doc.id,
        'name': doc.data()['name'] as String,
      }).toList();
    });
  }

  // -----------------------------------------------------------
  // МЕТОДЫ УПРАВЛЕНИЯ (ADMIN)
  // -----------------------------------------------------------

  // Создать/Обновить элемент
  Future<void> saveItem(String collectionName, String name, {String? id, bool isActive = true}) async {
    final data = {
      'name': name,
      'isActive': isActive,
    };

    if (id != null && id.isNotEmpty) {
      await _db.collection(collectionName).doc(id).update(data);
    } else {
      await _db.collection(collectionName).add(data);
    }
  }

  // Удалить элемент (архивация)
  Future<void> archiveItem(String collectionName, String id) async {
    await _db.collection(collectionName).doc(id).update({'isActive': false});
  }

  // -----------------------------------------------------------
  // МЕТОД МИГРАЦИИ (Migration to Collection Group structure)
  // -----------------------------------------------------------

  // Вспомогательный метод для удаления под-коллекции (Batch Delete)
  Future<void> _deleteCollection(String path) async {
    // В реальном проекте для массового удаления используется Cloud Function.
    // Здесь мы используем Dart для удаления пакетами по 50 документов.
    final snapshot = await _db.collection(path).limit(50).get();
    if (snapshot.docs.isNotEmpty) {
      final batch = _db.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      // Рекурсивный вызов для больших коллекций
      if (snapshot.docs.length == 50) {
        return _deleteCollection(path);
      }
    }
  }

  // ❗️ МЕТОД МИГРАЦИИ ФИЛЬТРОВ МАСТЕРА
  Future<void> migrateMasterFilterData(String masterId) async {
    final masterRef = _db.collection(_usersCollection).doc(masterId);
    final masterDoc = await masterRef.get();

    if (!masterDoc.exists) return;

    final data = masterDoc.data()!;
    // Предполагаем, что старые массивы содержат ID категорий/районов
    final List<String> oldCategories = List<String>.from(data['categories'] ?? []);
    final List<String> oldDistricts = List<String>.from(data['districts'] ?? []);

    // 1. Очистка старых под-коллекций
    await _deleteCollection('${_usersCollection}/$masterId/categories_index');
    await _deleteCollection('${_usersCollection}/$masterId/districts_index');

    // 2. Создание новых под-коллекций-индексов с полем 'id'
    final batch = _db.batch();

    // Перенос Категорий
    for (final categoryId in oldCategories) {
      // ✅ СОЗДАЕМ УНИКАЛЬНЫЙ ДОКУМЕНТ и храним ID категории внутри поля 'id'
      final newDocRef = masterRef.collection('categories_index').doc();
      batch.set(newDocRef, {'id': categoryId});
    }

    // Перенос Районов
    for (final districtId in oldDistricts) {
      final newDocRef = masterRef.collection('districts_index').doc();
      batch.set(newDocRef, {'id': districtId});
    }

    // 3. Очистка старых массивов в основном профиле
    batch.update(masterRef, {
      'categories': FieldValue.delete(),
      'districts': FieldValue.delete(),
    });

    await batch.commit();
  }
}