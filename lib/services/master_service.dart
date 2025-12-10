import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'dart:io';

class MasterService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final String _usersCollection = 'users';

  Future<void> toggleMasterStatus(String masterId, bool isAvailable) async {
    final newStatus = isAvailable
        ? AppConstants.masterStatusFree
        : AppConstants.masterStatusUnavailable;

    // ✅ ИСПРАВЛЕНИЕ: Обновляем и 'status', и 'isOnline', чтобы в базе был порядок
    await _db.collection(_usersCollection).doc(masterId).update({
      'status': newStatus,
      'isOnline': isAvailable,
    });
  }

  Future<void> updateMasterProfile(MasterProfile profile) async {
    await _db.collection(_usersCollection).doc(profile.uid).update({
      'priceList': profile.priceList,
      'achievements': profile.achievements,
    });
  }

  Future<void> updateMasterSearchFilters(String masterId, List<String> categoryIds, List<String> districtIds) async {
    await _db.collection(_usersCollection).doc(masterId).update({
      'categories': categoryIds,
      'districts': districtIds,
    });
  }

  Future<MasterProfile?> getProfileData(String masterId) async {
    try {
      final doc = await _db.collection(_usersCollection).doc(masterId).get();
      if (doc.exists && doc.data() != null) {
        return MasterProfile.fromFirestore({...doc.data()!, 'uid': doc.id});
      }
      return null;
    } catch (e) {
      print('Error getting master profile: $e');
      return null;
    }
  }

  Future<void> submitVerificationDocs({
    required String masterId,
    required File selfieFile,
    required File docFile,
  }) async {
    final storagePath = 'verification/$masterId';
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

  Future<List<MasterProfile>> searchMasters({
    String? categoryId,
    String? districtId,
    bool onlyFree = false,
  }) async {
    try {
      Query query = _db.collection(_usersCollection)
          .where('role', isEqualTo: 'master')
          .where('verificationStatus', isEqualTo: AppConstants.verificationVerified);

      if (categoryId != null && categoryId.isNotEmpty) {
        query = query.where('categories', arrayContains: categoryId);
      }

      if (onlyFree) {
        query = query.where('status', isEqualTo: AppConstants.masterStatusFree);
      }

      final snapshot = await query.get();

      List<MasterProfile> masters = snapshot.docs.map((doc) {
        return MasterProfile.fromFirestore({...doc.data()! as Map<String, dynamic>, 'uid': doc.id});
      }).toList();

      if (districtId != null && districtId.isNotEmpty) {
        masters = masters.where((m) =>
            m.districts.contains(districtId)
        ).toList();
      }

      masters.sort((a, b) => b.rating.compareTo(a.rating));

      return masters;

    } catch (e) {
      print("Search Error: $e");
      return [];
    }
  }
}