// master_map_data.dart

import 'package:google_maps_flutter/google_maps_flutter.dart';
// !!! ИСПРАВЛЕНО: Добавлен префикс 'fs' для устранения конфликта имен GeoPoint
import 'package:cloud_firestore/cloud_firestore.dart' as fs;
// Используем ваш существующий профиль
import 'master_profile.dart';

class MasterMapData {
  // Ваш существующий профиль мастера
  final MasterProfile profile;
  // Местоположение в формате LatLng для Google Maps
  final LatLng lastLocation;
  // Рассчитанное расстояние до клиента (в км)
  final double distanceKm;

  MasterMapData({
    required this.profile,
    required this.lastLocation,
    required this.distanceKm,
  });

  // Фабричный метод для MasterSearchService
  factory MasterMapData.fromMap(
      Map<String, dynamic> data, String id, double distanceKm) {

    // 1. Создание MasterProfile
    // Передаем id как uid, так как id документа Firestore = uid мастера
    final profile = MasterProfile.fromFirestore({...data, 'uid': id});

    // 2. Извлечение GeoPoint для LatLng
    // !!! ИСПРАВЛЕНО: Используем fs.GeoPoint
    final fs.GeoPoint? geoPoint = data['lastLocation'] as fs.GeoPoint?;

    if (geoPoint == null) {
      throw ArgumentError('lastLocation is missing or invalid for Master ID: $id');
    }

    return MasterMapData(
      profile: profile,
      lastLocation: LatLng(geoPoint.latitude, geoPoint.longitude),
      distanceKm: distanceKm,
    );
  }
}