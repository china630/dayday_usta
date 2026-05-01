import 'package:cloud_firestore/cloud_firestore.dart';

/// Агрегаты по категории (см. PRD §5.1, коллекция `category_metrics` на сервере).
class CategoryMetricsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  String _docId(String category) {
    final c = category.trim().replaceAll('/', '_');
    if (c.isEmpty) return 'unknown';
    return c.length > 200 ? c.substring(0, 200) : c;
  }

  Future<double?> getAvgFirstAcceptSeconds(String category) async {
    try {
      final doc = await _db.collection('category_metrics').doc(_docId(category)).get();
      if (!doc.exists) return null;
      final v = doc.data()?['avgFirstAcceptSeconds'];
      if (v is num) return v.toDouble();
      return null;
    } catch (_) {
      return null;
    }
  }
}
