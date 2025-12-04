import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
// Мы используем geolocator, который более стабилен, чем background_location

class LocationService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Конфигурация для получения фоновых обновлений
  static const int LOCATION_INTERVAL_SECONDS = 10;
  // ✅ ИСПРАВЛЕНО: Изменен тип с double на int, чтобы соответствовать LocationSettings.distanceFilter
  static const int LOCATION_DISTANCE_FILTER_METERS = 10;

  // Поток для подписки на обновления местоположения
  StreamSubscription<Position>? _positionStreamSubscription;

  Future<void> startLocationUpdates() async {
    final user = _auth.currentUser;
    if (user == null) {
      print('LocationService: Master not logged in.');
      return;
    }

    // 1. Проверка разрешений и сервисов
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled.');
      return;
    }

    // Проверка и запрос разрешения "Always" (для фоновой работы)
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.always) {
      permission = await Geolocator.requestPermission();
      if (permission != LocationPermission.always) {
        print('Background location permission not granted.');
        return;
      }
    }

    // 2. Определение настроек для потока
    // ✅ ИСПРАВЛЕНО: УБРАНЫ ВСЕ ПЛАТФОРМЕННЫЕ НАСТРОЙКИ (androidSettings, platformSettings),
    // так как они вызывали ошибку 'No named parameter' в вашей версии geolocator.
    // Оставляем только базовые const параметры, которые работают во всех версиях.
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high, // Высокая точность
      // Теперь distanceFilter ожидает int, и мы передаем int
      distanceFilter: LOCATION_DISTANCE_FILTER_METERS,

      // Интервал и другие специфичные настройки будут контролироваться самой ОС,
      // поскольку мы не можем их задать через LocationSettings.
    );

    // 3. Запуск слушателя
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      // 4. Логика записи в Firestore при получении новой позиции
      final newLocation = {
        'lastLocation': GeoPoint(position.latitude, position.longitude),
        'lastLocationTimestamp': FieldValue.serverTimestamp(),
        'status': 'free', // Мастер свободен, пока не примет заказ
      };

      try {
        await _firestore.collection('users').doc(user.uid).update(newLocation);
        print(
            'LocationService: Location updated successfully: ${position.latitude}, ${position.longitude}');
      } catch (e) {
        print('LocationService: Error updating location in Firestore: $e');
      }
    });

    print('LocationService: Location stream started using Geolocator.');
  }

  // Остановка фонового сервиса, когда Мастер переходит в "Оффлайн"
  Future<void> stopLocationUpdates() async {
    // Останавливаем подписку на поток
    await _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;

    final user = _auth.currentUser;
    if (user != null) {
      // Обновить статус Мастера на "offline"
      await _firestore.collection('users').doc(user.uid).update({'status': 'offline'});
    }
    print('LocationService: Location updates stopped and master status set to offline.');
  }
}