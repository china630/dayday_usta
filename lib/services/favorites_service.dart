import 'package:cloud_firestore/cloud_firestore.dart';

class FavoritesService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> setFavorite(String clientUserId, String masterId, bool add) async {
    final ref = _db.collection('users').doc(clientUserId);
    if (add) {
      await ref.update({'favoriteMasterIds': FieldValue.arrayUnion([masterId])});
    } else {
      await ref.update({'favoriteMasterIds': FieldValue.arrayRemove([masterId])});
    }
  }

  Stream<List<String>> favoriteMasterIdsStream(String clientUserId) {
    return _db.collection('users').doc(clientUserId).snapshots().map((snap) {
      if (!snap.exists) return <String>[];
      final data = snap.data();
      return List<String>.from(data?['favoriteMasterIds'] ?? []);
    });
  }
}
