// lib/screens/map_screen.dart (Финальная Рабочая Версия)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bolt_usta/services/master_search_service.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_map_data.dart';
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/screens/order_search_screen.dart'; // Для перехода на экран поиска
import 'package:collection/collection.dart';

class MapScreen extends StatefulWidget {
  final String currentUserId;

  const MapScreen({super.key, required this.currentUserId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const CameraPosition _initialCameraPosition = CameraPosition(
    target: LatLng(40.377033, 49.830602),
    zoom: 12,
  );

  GoogleMapController? mapController;
  Position? _currentPosition;
  bool _isLoading = true;
  String _locationError = '';

  final MasterSearchService _searchService = MasterSearchService();
  StreamSubscription<List<MasterMapData>>? _masterStreamSubscription;
  List<MasterMapData> _availableMasters = [];

  String? _selectedCategory;
  bool _isOrderProcessing = false;

  @override
  void initState() {
    super.initState();
    // Устанавливаем первую категорию по умолчанию
    _selectedCategory = AppConstants.serviceCategories.firstOrNull;
    _determinePosition();
  }

  @override
  void dispose() {
    _masterStreamSubscription?.cancel();
    super.dispose();
  }

  // Методы определения позиции и старта поиска... (оставлены без изменений)

  Future<void> _determinePosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });
      _startMasterSearch(position, _selectedCategory);
    } catch (e) {
      setState(() {
        _locationError = 'Не удалось получить ваше местоположение: $e';
        _isLoading = false;
      });
    }
  }

  void _startMasterSearch(Position position, String? category) {
    _masterStreamSubscription?.cancel();
    if (category == null) return;

    _masterStreamSubscription = _searchService
        .streamAvailableMasters(position.latitude, position.longitude, category)
        .listen(_onNewMasterList, onError: (e) {
      print('Error streaming masters: $e');
    });
  }

  void _onNewMasterList(List<MasterMapData> newMasters) {
    setState(() {
      _availableMasters = newMasters;
    });
  }

  Set<Marker> _createMarkers() {
    // ... (логика создания маркеров)
    final Set<Marker> markers = {};

    // 1. Маркеры доступных мастеров
    for (var master in _availableMasters) {
      markers.add(
        Marker(
          markerId: MarkerId(master.profile.uid),
          position: master.lastLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: InfoWindow(
            title: master.profile.fullName,
            snippet: 'Рейтинг: ${master.profile.rating.toStringAsFixed(1)} | ${master.distanceKm.toStringAsFixed(1)} км',
          ),
        ),
      );
    }

    // 2. Маркер текущей позиции клиента (Красный)
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('clientLocation'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Ваше местоположение'),
        ),
      );
    }
    return markers;
  }

  // P2.4: Инициация срочного заказа (переход на OrderSearchScreen)
  Future<void> _initiateEmergencyOrder() async {
    if (_currentPosition == null || _selectedCategory == null || _isOrderProcessing) return;

    setState(() { _isOrderProcessing = true; });

    try {
      // Инициация заказа НЕ здесь, а на OrderSearchScreen, чтобы таймер шел сразу

      if (mounted) {
        // Переход на экран поиска/ожидания заказа (II. Логика Неудачного Поиска)
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => OrderSearchScreen(
              clientUserId: widget.currentUserId,
              category: _selectedCategory!,
              clientLocation: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при подготовке заказа: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() { _isOrderProcessing = false; });
      }
    }
  }

  void _onCategoryChanged(String? newCategory) {
    if (newCategory == null) return;
    setState(() {
      _selectedCategory = newCategory;
    });
    if (_currentPosition != null) {
      _startMasterSearch(_currentPosition!, newCategory);
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_locationError.isNotEmpty) {
      return Scaffold(body: Center(child: Text(_locationError, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))));
    }

    final initialTarget = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final markers = _createMarkers();
    final masterCountText = 'Найдено доступных мастеров: ${_availableMasters.length}';
    final isMasterAvailable = _availableMasters.isNotEmpty;

    return Scaffold(
      body: Stack(
        children: [
          // КАРТА и МАРКЕРЫ
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(target: initialTarget, zoom: 14),
            onMapCreated: (controller) => mapController = controller,
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
          ),

          // P2.2: Выбор категории (Фильтр)
          Positioned(
            top: 40,
            left: 10,
            right: 10,
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      masterCountText,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    DropdownButton<String>(
                      value: _selectedCategory,
                      hint: const Text('Выберите категорию'),
                      isExpanded: true,
                      onChanged: _onCategoryChanged,
                      items: AppConstants.serviceCategories.map((String value) {
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // P2.4: Кнопка быстрого срочного заказа (Восстановлена)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: ElevatedButton(
              onPressed: isMasterAvailable && !_isOrderProcessing ? _initiateEmergencyOrder : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isMasterAvailable ? Colors.deepOrange : Colors.grey,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 5,
              ),
              child: _isOrderProcessing
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                isMasterAvailable ? 'SÜRATLİ SİFARİŞ (BOLT)' : 'Мастера недоступны',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}