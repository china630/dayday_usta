import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
// ✅ ИСПОЛЬЗУЕМ ПРЕФИКС 'gh', чтобы избежать конфликта имен GeoPoint
import 'package:flutter_geo_hash/flutter_geo_hash.dart' as gh;

class LocationManager extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionStreamSubscription;
  Position? _currentPosition;
  String? _masterId;
  bool _isTracking = false;

  // Геттер для получения текущей позиции
  Position? get currentPosition => _currentPosition;

  // Инициализация менеджера
  Future<void> init(String masterId) async {
    _masterId = masterId;
    await _checkPermissions();
  }

  // Запуск отслеживания
  void startTracking() {
    if (_isTracking) return;
    _isTracking = true;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 50, // Обновлять каждые 50 метров
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      _currentPosition = position;
      _updateLocationInFirestore(position);
      notifyListeners(); // Уведомляем UI об изменении позиции
    });
  }

  // Остановка отслеживания
  void stopTracking() {
    _positionStreamSubscription?.cancel();
    _isTracking = false;
    _currentPosition = null;
    notifyListeners();
  }

  // Обновление локации в Firestore
  Future<void> _updateLocationInFirestore(Position position) async {
    if (_masterId == null) return;

    // ✅ ИСПОЛЬЗУЕМ gh.GeoPoint для генерации хеша
    final geoHash = gh.MyGeoHash().geoHashForLocation(gh.GeoPoint(position.latitude, position.longitude));

    try {
      await _firestore.collection('users').doc(_masterId).update({
        // ✅ ИСПОЛЬЗУЕМ ОБЫЧНЫЙ GeoPoint (из cloud_firestore) для сохранения в базу
        'lastLocation': GeoPoint(position.latitude, position.longitude),
        'geoHash': geoHash,
        'lastActive': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Error updating location: $e");
    }
  }

  Future<void> _checkPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Location services are disabled.');
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Location permissions are denied');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Location permissions are permanently denied.');
    }
  }

  @override
  void dispose() {
    stopTracking();
    super.dispose();
  }
}