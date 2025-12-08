import 'package:cloud_firestore/cloud_firestore.dart';

class MetadataService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Кэш
  List<String>? _cachedCategories;
  List<String>? _cachedDistricts;

  // Получение категорий
  Future<List<String>> getCategories() async {
    if (_cachedCategories != null && _cachedCategories!.isNotEmpty) {
      return _cachedCategories!;
    }

    try {
      // Читаем из коллекции 'categories', берем поле 'name' или ID документа
      final snapshot = await _db.collection('categories').get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        return (data['name'] as String?) ?? doc.id;
      }).toList();

      list.sort();

      if (list.isNotEmpty) {
        _cachedCategories = list;
        return list;
      }
    } catch (e) {
      print("Error fetching categories: $e");
    }

    // ✅ При ошибке возвращаем пустой список (обработка отсутствия сети на уровне UI)
    return [];
  }

  // Получение районов
  Future<List<String>> getDistricts() async {
    if (_cachedDistricts != null && _cachedDistricts!.isNotEmpty) {
      return _cachedDistricts!;
    }

    try {
      final snapshot = await _db.collection('districts').get();

      final list = snapshot.docs.map((doc) {
        final data = doc.data();
        return (data['name'] as String?) ?? doc.id;
      }).toList();

      list.sort();

      if (list.isNotEmpty) {
        _cachedDistricts = list;
        return list;
      }
    } catch (e) {
      print("Error fetching districts: $e");
    }

    return [];
  }
}