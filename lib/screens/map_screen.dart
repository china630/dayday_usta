import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:bolt_usta/services/master_search_service.dart';
import 'package:bolt_usta/services/metadata_service.dart';
import 'package:bolt_usta/models/master_map_data.dart';
import 'package:bolt_usta/screens/order_tracking_screen.dart';
import 'package:bolt_usta/screens/client/modals/order_creation_modal.dart'; // Путь может отличаться в зависимости от вашей структуры
import 'package:bolt_usta/core/app_colors.dart';

class MapScreen extends StatefulWidget {
  final String currentUserId;

  const MapScreen({super.key, required this.currentUserId});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  GoogleMapController? mapController;
  Position? _currentPosition;
  bool _isLoading = true;
  String _locationError = '';

  final MasterSearchService _searchService = MasterSearchService();
  final MetadataService _metadataService = MetadataService();

  StreamSubscription<List<MasterMapData>>? _masterStreamSubscription;
  List<MasterMapData> _availableMasters = [];

  List<String> _categories = [];
  String? _selectedCategory;
  String? _mapStyle;

  @override
  void initState() {
    super.initState();
    _initMapData();
  }

  Future<void> _initMapData() async {
    await _loadMapStyle();
    final cats = await _metadataService.getCategories();
    if (mounted) {
      setState(() {
        _categories = cats;
        _selectedCategory = null;
      });
      _determinePosition();
    }
  }

  Future<void> _loadMapStyle() async {
    try {
      _mapStyle = await rootBundle.loadString('assets/map_style.json');
    } catch (e) {
      debugPrint("Ошибка загрузки стиля: $e");
    }
  }

  @override
  void dispose() {
    _masterStreamSubscription?.cancel();
    super.dispose();
  }

  Future<void> _determinePosition() async {
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = position;
        _isLoading = false;
      });
      if (_selectedCategory != null) {
        _startMasterSearch(position, _selectedCategory);
      }
    } catch (e) {
      setState(() {
        _locationError = 'Lokasiya xətası: $e';
        _isLoading = false;
      });
    }
  }

  void _startMasterSearch(Position position, String? category) {
    _masterStreamSubscription?.cancel();
    if (category == null) return;

    _masterStreamSubscription = _searchService
        .streamAvailableMasters(position.latitude, position.longitude, category)
        .listen(_onNewMasterList, onError: (e) => print('Search error: $e'));
  }

  void _onNewMasterList(List<MasterMapData> newMasters) {
    if (mounted) setState(() => _availableMasters = newMasters);
  }

  Set<Marker> _createMarkers() {
    final Set<Marker> markers = {};
    for (var master in _availableMasters) {
      markers.add(
        Marker(
          markerId: MarkerId(master.profile.uid),
          position: master.lastLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: master.profile.fullName),
        ),
      );
    }
    if (_currentPosition != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('clientLocation'),
          position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      );
    }
    return markers;
  }

  void _onCategoryChanged(String? newCategory) {
    if (newCategory == null) return;
    setState(() => _selectedCategory = newCategory);
    if (_currentPosition != null) {
      _startMasterSearch(_currentPosition!, newCategory);
    }
  }

  Future<void> _openOrderCreationModal() async {
    if (_currentPosition == null || _selectedCategory == null) return;

    // ✅ ИСПРАВЛЕНИЕ: Разрешаем срочный заказ всегда (для теста), даже если мастеров 0
    // Если вы хотите строгую логику, верните: _availableMasters.isNotEmpty
    const bool canDoEmergency = true;

    final result = await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OrderCreationModal(
        clientUserId: widget.currentUserId,
        category: _selectedCategory!,
        location: GeoPoint(_currentPosition!.latitude, _currentPosition!.longitude),
        targetMasterId: null,
        allowEmergency: canDoEmergency,
      ),
    );

    if (result != null && result is Map<String, dynamic> && mounted) {
      final orderId = result['orderId'];
      final mode = result['mode'];

      if (mode == 'emergency') {
        // Переход на экран таймера
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OrderTrackingScreen(
              orderId: orderId,
              clientLocation: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sifariş planlaşdırıldı!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_locationError.isNotEmpty) return Scaffold(body: Center(child: Text(_locationError, style: const TextStyle(color: Colors.red))));

    final initialTarget = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    final markers = _createMarkers();
    final bool isCategorySelected = _selectedCategory != null;

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(target: initialTarget, zoom: 15),
            onMapCreated: (controller) {
              mapController = controller;
              if (_mapStyle != null) mapController!.setMapStyle(_mapStyle);
            },
            markers: markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Фильтр
          Positioned(
            top: 60,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Nəyi təmir edirik?', style: TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 5),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedCategory,
                      isExpanded: true,
                      hint: Text("Kateqoriya Seç", style: TextStyle(color: kDarkColor.withOpacity(0.5), fontSize: 18, fontWeight: FontWeight.w600)),
                      icon: const Icon(Icons.keyboard_arrow_down, color: kPrimaryColor),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor),
                      onChanged: _onCategoryChanged,
                      items: _categories.map((val) => DropdownMenuItem(value: val, child: Text(val))).toList(),
                    ),
                  ),
                  if (isCategorySelected)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle),
                            child: const Icon(Icons.people, size: 14, color: kPrimaryColor),
                          ),
                          const SizedBox(width: 8),
                          Text('${_availableMasters.length} usta yaxınlıqda', style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
                ],
              ),
            ),
          ),

          // Кнопка
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isCategorySelected ? _openOrderCreationModal : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryColor,
                  disabledBackgroundColor: Colors.grey[300],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 5,
                ),
                child: const Text('USTA ÇAĞIR', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}