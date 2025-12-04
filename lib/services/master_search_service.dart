// master_search_service.dart

import 'package:cloud_firestore/cloud_firestore.dart' as fs;
import 'package:rxdart/rxdart.dart';
import 'package:geolocator/geolocator.dart';

// Используем flutter_geo_hash с префиксом geo
import 'package:flutter_geo_hash/flutter_geo_hash.dart' as geo;

import '../models/master_map_data.dart';

class MasterSearchService {

  final fs.FirebaseFirestore _firestore = fs.FirebaseFirestore.instance;

  static const double _searchRadiusKm = 10.0;
  static const double _searchRadiusMeters = _searchRadiusKm * 1000;

  // !!! ФИНАЛЬНОЕ ИСПРАВЛЕНИЕ: Создаем экземпляр MyGeoHash
  final geo.MyGeoHash geohashUtil = geo.MyGeoHash();

  Stream<List<MasterMapData>> streamAvailableMasters(
      double latitude, double longitude, String category) {

    // 1. Создаем GeoPoint центра (для передачи в MyGeoHash)
    final geo.GeoPoint centerPoint = geo.GeoPoint(latitude, longitude);

    // 2. Рассчитываем GeoHash-границы для запроса
    // !!! ИСПРАВЛЕНИЕ: Вызываем метод через экземпляр geohashUtil
    final List<List<String>> bounds = geohashUtil.geohashQueryBounds(
        centerPoint, _searchRadiusMeters);

    // Массив для хранения потоков (Streams) от каждого GeoHash-диапазона
    final streams = <Stream<fs.QuerySnapshot>>[];

    // 3. Создаем целевой запрос Firestore для каждого диапазона
    for (final bound in bounds) {
      fs.Query query = _firestore.collection('users')
          .orderBy('geoHash')
          .startAt([bound[0]])
          .endAt([bound[1]])
          .where('role', isEqualTo: 'master')
          .where('status', isEqualTo: 'free')
          .where('verificationStatus', isEqualTo: 'verified')
          .where('categories', arrayContains: category);

      streams.add(query.snapshots() as Stream<fs.QuerySnapshot>);
    }

    // 4. Объединяем все потоки в один и обрабатываем данные
    return Rx.merge(streams).map((snapshot) {
      final List<MasterMapData> masters = [];

      for (final doc in snapshot.docs) {
        final masterId = doc.id;
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
              masters.add(MasterMapData.fromMap(data, masterId, distanceKm));
            }
          }
        }
      }
      return masters;
    });
  }
}