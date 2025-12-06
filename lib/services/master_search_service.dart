// lib/services/master_search_service.dart

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:rxdart/rxdart.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_geo_hash/flutter_geo_hash.dart' as geo;
import 'package:flutter/foundation.dart';
import '../models/master_map_data.dart';

class MasterSearchService {
  final fs.FirebaseFirestore _firestore = fs.FirebaseFirestore.instance;

  static const double _searchRadiusKm = 10.0;
  static const double _searchRadiusMeters = _searchRadiusKm * 1000;

  final geo.MyGeoHash geohashUtil = geo.MyGeoHash();

  Stream<List<MasterMapData>> streamAvailableMasters(
      double latitude, double longitude, String category) {

    final geo.GeoPoint centerPoint = geo.GeoPoint(latitude, longitude);
    final List<List<String>> bounds = geohashUtil.geohashQueryBounds(
        centerPoint, _searchRadiusMeters);

    debugPrint("🔍 ПОИСК НАЧАТ: Cat='$category', Lat=$latitude, Lng=$longitude");
    debugPrint("📊 GeoHash секторов: ${bounds.length}");

    final streams = <Stream<List<MasterMapData>>>[];

    for (int i = 0; i < bounds.length; i++) {
      final bound = bounds[i];

      // Формируем запрос
      fs.Query query = _firestore.collection('users')
          .orderBy('geoHash')
          .startAt([bound[0]])
          .endAt([bound[1]])
          .where('role', isEqualTo: 'master')
          .where('status', isEqualTo: 'free')
          .where('verificationStatus', isEqualTo: 'verified')
          .where('categories', arrayContains: category);

      // Преобразуем Stream<QuerySnapshot> сразу в Stream<List<MasterMapData>>
      // и добавляем обработку ошибок для КАЖДОГО потока отдельно
      final stream = query.snapshots().map((snapshot) {
        final List<MasterMapData> localMasters = [];
        for (final doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data != null) {
            final fs.GeoPoint? geoPoint = data['lastLocation'] as fs.GeoPoint?;
            if (geoPoint != null) {
              final distanceMeters = Geolocator.distanceBetween(
                latitude, longitude,
                geoPoint.latitude, geoPoint.longitude,
              );
              final distanceKm = distanceMeters / 1000;
              if (distanceKm <= _searchRadiusKm) {
                localMasters.add(MasterMapData.fromMap(data, doc.id, distanceKm));
              }
            }
          }
        }
        // debugPrint("  ✅ Сектор $i: найдено ${localMasters.length} мастеров");
        return localMasters;
      }).handleError((error) {
        debugPrint("  ❌ ОШИБКА в секторе $i: $error");
        // Возвращаем пустой список при ошибке, чтобы не блокировать остальные сектора
        return <MasterMapData>[];
      });

      streams.add(stream);
    }

    // Собираем результаты
    return Rx.combineLatest(streams, (List<List<MasterMapData>> results) {
      final List<MasterMapData> allMasters = [];
      final Set<String> addedIds = {};

      for (var list in results) {
        for (var master in list) {
          if (!addedIds.contains(master.profile.uid)) {
            allMasters.add(master);
            addedIds.add(master.profile.uid);
          }
        }
      }

      allMasters.sort((a, b) => a.distanceKm.compareTo(b.distanceKm));
      debugPrint("🏁 ИТОГ: Найдено уникальных мастеров: ${allMasters.length}");
      return allMasters;
    });
  }
}