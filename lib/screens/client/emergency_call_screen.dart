// Файл: lib/screens/client/emergency_call_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart'; // ✅ Важный импорт
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/screens/client/active_order_screen.dart'; // Проверь этот путь
import 'dart:async';

class EmergencyCallScreen extends StatefulWidget {
  final String customerId;

  const EmergencyCallScreen({required this.customerId, super.key});

  @override
  State<EmergencyCallScreen> createState() => _EmergencyCallScreenState();
}

class _EmergencyCallScreenState extends State<EmergencyCallScreen> {
  final OrderService _orderService = OrderService();
  String? _selectedCategory;
  final TextEditingController _descriptionController = TextEditingController();
  bool _isLoading = false;
  String? _locationError;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _determinePosition();
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // --- 1. ГЕОЛОКАЦИЯ ---
  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationError = 'Zəhmət olmasa, GPS xidmətini yandırın.');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationError = 'Yerləşməyə icazə verilmədi.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationError = 'Yerləşməyə icazə bloklanıb.');
      return false;
    }

    _locationError = null;
    return true;
  }

  Future<void> _determinePosition() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _locationError = null;
    });

    if (!await _handleLocationPermission()) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      // Пытаемся получить координаты с таймаутом
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      ).timeout(const Duration(seconds: 10));

      setState(() {
        _currentPosition = position;
        _locationError = null;
      });
    } on TimeoutException {
      setState(() => _locationError = 'Yerləşmə təyin edilmədi (Timeout).');
    } catch (e) {
      setState(() => _locationError = 'Xəta: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // --- 2. ВЫЗОВ МАСТЕРА (CLOUD FUNCTION) ---
  Future<void> _callMaster() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kateqoriya seçin.')));
      return;
    }
    // Если координат нет — пробуем найти снова
    if (_currentPosition == null) {
      await _determinePosition();
      if (_currentPosition == null) return;
    }

    setState(() => _isLoading = true);

    try {
      // ✅ ГЛАВНОЕ: Вызов Cloud Function через сервис
      final clientLatLng = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);

      print("DEBUG: Начинаем вызов Cloud Function...");

      final orderId = await _orderService.initiateEmergencyOrder(
        clientUserId: widget.customerId,
        category: _selectedCategory!,
        clientLocation: clientLatLng,
      );

      print("DEBUG: Cloud Function успешно отработала. Order ID: $orderId");

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ActiveOrderScreen(orderId: orderId)),
        );
      }

    } catch (e) {
      print('Ошибка OrderService: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xəta: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Логика блокировки кнопки
    final bool isLocationReady = _currentPosition != null;
    final bool isBusy = _isLoading;
    final bool hasError = _locationError != null;
    final bool isButtonEnabled = isLocationReady && !isBusy && !hasError;

    return Scaffold(
      appBar: AppBar(title: const Text('Təcili Usta Çağır')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Категория
            const Text('Kateqoriya:', style: TextStyle(fontWeight: FontWeight.bold)),
            DropdownButtonFormField<String>(
              hint: const Text('Seçin'),
              value: _selectedCategory,
              items: AppConstants.serviceCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _selectedCategory = v),
            ),
            const SizedBox(height: 20),

            // Локация
            const Text('Məkan:', style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.grey[100],
              child: Row(
                children: [
                  Icon(Icons.location_on, color: hasError ? Colors.red : (isLocationReady ? Colors.green : Colors.grey)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hasError ? _locationError!
                          : (isLocationReady ? 'Hazır: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}'
                          : 'Məkan axtarılır...'),
                    ),
                  ),
                  if (!isLocationReady && !hasError) const CircularProgressIndicator.adaptive(),
                  IconButton(icon: const Icon(Icons.refresh), onPressed: _determinePosition),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Описание
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Problem təsviri', border: OutlineInputBorder()),
              maxLines: 2,
            ),
            const SizedBox(height: 40),

            // Кнопка
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                // Если GPS нет — кнопка серая (null)
                onPressed: isButtonEnabled ? _callMaster : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('ÇAĞIR (TEST)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}