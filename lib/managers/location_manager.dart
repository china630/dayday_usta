// lib/managers/location_manager.dart (Обновленный код)

import 'package:flutter/material.dart';
import '../services/location_service.dart';
// ✅ НОВЫЙ ИМПОРТ: Для обновления статуса в Firestore
import 'package:bolt_usta/services/master_service.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Для получения UID

class LocationManager extends ChangeNotifier {
  final LocationService _locationService = LocationService();
  final MasterService _masterService = MasterService(); // Новый сервис

  bool _isOnline = false;
  String? _masterId;

  bool get isOnline => _isOnline;

  // Инициализация
  LocationManager() {
    _masterId = FirebaseAuth.instance.currentUser?.uid;
  }

  // ✅ МОДИФИКАЦИЯ: Добавляем целевое значение статуса (для MasterDashboardScreen)
  Future<void> toggleOnlineStatus([bool? targetStatus]) async {
    if (_masterId == null) {
      // Невозможно изменить статус, если пользователь не аутентифицирован
      print('LocationManager Error: Master ID is null.');
      return;
    }

    final bool newStatus = targetStatus ?? !_isOnline;

    if (newStatus) {
      // 1. Переход в ОНЛАЙН (FREE)
      try {
        await _locationService.startLocationUpdates();
        await _masterService.toggleMasterStatus(_masterId!, true); // Обновляем Firestore на 'free'
        _isOnline = true;
        print('LocationManager: Switched to ONLINE (FREE).');
      } catch (e) {
        print('LocationManager Error: Failed to start location service: $e');
        _isOnline = false; // Откат
        // Если не удалось, статус в Firestore остается неизменным
      }
    } else {
      // 2. Переход в ОФФЛАЙН (BUSY)
      await _locationService.stopLocationUpdates();
      await _masterService.toggleMasterStatus(_masterId!, false); // Обновляем Firestore на 'busy'
      _isOnline = false;
      print('LocationManager: Switched to OFFLINE (BUSY).');
    }

    notifyListeners();
  }

  Future<void> stopOnlineServiceOnSignOut() async {
    if (_isOnline) {
      // Остановка GPS сервиса
      await _locationService.stopLocationUpdates();
      // Установка статуса в Firestore как 'busy' перед выходом
      if (_masterId != null) {
        await _masterService.toggleMasterStatus(_masterId!, false);
      }
      _isOnline = false;
      notifyListeners();
      print('LocationManager: Location service stopped before sign out.');
    }
  }
}