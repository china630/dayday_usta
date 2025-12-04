import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/screens/customer/active_order_screen.dart';
import 'dart:async'; // 💡 ИСПРАВЛЕНИЕ: Добавлен импорт для TimeoutException

class EmergencyCallScreen extends StatefulWidget {
  final String customerId;

  const EmergencyCallScreen({required this.customerId, super.key});

  @override
  State<EmergencyCallScreen> createState() => _EmergencyCallScreenState();
}

class _EmergencyCallScreenState extends State<EmergencyCallScreen> {
  final OrderService _orderService = OrderService();
  String? _selectedCategory; // Kateqoriya
  final TextEditingController _descriptionController = TextEditingController();
  bool _isLoading = false;
  String? _locationError;
  Position? _currentPosition;

  @override
  void initState() {
    super.initState();
    // Вызываем асинхронную функцию после завершения отрисовки фрейма
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _determinePosition();
    });
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // ЛОГИКА ГЕОЛОКАЦИИ (Geolocator)
  // --------------------------------------------------------------------------

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _locationError = 'Zəhmət olmasa, GPS/Yerləşmə xidmətlərini yandırın.';
      });
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _locationError = 'Yerləşməyə giriş rədd edildi.';
        });
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _locationError = 'Yerləşməyə giriş qəti qadağandır. Tətbiq parametrlərini yoxlayın.';
      });
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
      // ✅ ДОБАВЛЕН ТАЙМ-АУТ, чтобы избежать зависания ANR
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high
      ).timeout(const Duration(seconds: 10)); // Таймаут 10 секунд

      setState(() {
        _currentPosition = position;
        _locationError = null;
      });
    } on TimeoutException { // ✅ ИСПРАВЛЕНИЕ: Теперь TimeoutException распознается
      setState(() {
        _locationError = 'Yerləşmə təyin edilmədi. Vaxt başa çatdı.'; // Таймаут
      });
    } catch (e) {
      setState(() {
        _locationError = 'Yerləşməni təyin edərkən xəta: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }


  // --------------------------------------------------------------------------
  // ЛОГИКА СОЗДАНИЯ ЗАКАЗА (Срочный Вызов)
  // --------------------------------------------------------------------------

  Future<void> _callMaster() async {
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zəhmət olmasa, Kateqoriya seçin.')),
      );
      return;
    }
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yerləşmə məlumatı yoxdur. Yenidən cəhd edin.')),
      );
      // Если позиции нет, пытаемся определить ее снова
      await _determinePosition();
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Фиксируем координаты для Firestore
      final clientGeoPoint = GeoPoint(
          _currentPosition!.latitude,
          _currentPosition!.longitude
      );

      // 2. Создаём Заказ
      final orderId = await _orderService.createEmergencyOrder(
        customerId: widget.customerId,
        category: _selectedCategory!,
        problemDescription: _descriptionController.text.trim(),
        clientLocation: clientGeoPoint,
      );

      // 3. Навигация на экран отслеживания
      if (mounted) {
        // Замена текущего экрана на экран Активного Заказа
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => ActiveOrderScreen(orderId: orderId)),
        );
      }

    } catch (e) {
      print('Ошибка при вызове мастера: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sifariş yaratmaqda xəta baş verdi.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // --------------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Определяем статус для индикатора загрузки
    final isDeterminingLocation = _currentPosition == null && _locationError == null && _isLoading;
    final isButtonDisabled = _isLoading || _currentPosition == null || _locationError != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Təcili Usta Çağır')), // Срочный вызов мастера
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Поле выбора "Kateqoriya" (Категория)
            const Text('1. Usta Kateqoriyasını Seçin:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(border: OutlineInputBorder()),
              hint: const Text('Kateqoriya'),
              value: _selectedCategory,
              items: AppConstants.serviceCategories.map((String category) {
                return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category)
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() => _selectedCategory = newValue);
              },
            ),

            const SizedBox(height: 30),

            // 2. Геолокация и Статус
            const Text('2. Yerləşmə Məlumatı:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on,
                      color: _locationError != null ? Colors.red : (_currentPosition != null ? Colors.green : Colors.grey)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _locationError ?? (_currentPosition != null
                          ? 'Koordinatlar alınıb: ${_currentPosition!.latitude.toStringAsFixed(4)}...' // Координаты получены
                          : 'Yerləşmə təyin edilir...' // Местоположение определяется
                      ),
                      style: TextStyle(color: _locationError != null ? Colors.red : Colors.black87),
                    ),
                  ),
                  if (isDeterminingLocation) // Индикатор загрузки местоположения
                    SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue.shade700)
                    ),
                  if (_locationError != null) // Кнопка перезагрузки
                    IconButton(icon: const Icon(Icons.refresh), onPressed: _determinePosition),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 3. Поле "Problemin Qısa Təsviri"
            const Text('3. Problemi Qısa Təsvir Edin:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'Məsələn: Soyuducu işləmir...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),

            const SizedBox(height: 50),

            // 4. Кнопка "Təcili Usta Çağır"
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: isButtonDisabled ? null : _callMaster,
                icon: _isLoading
                    ? const SizedBox.shrink()
                    : const Icon(Icons.send, color: Colors.white),
                label: Text(
                  _isLoading ? 'Sifariş göndərilir...' : 'Təcili Usta Çağır',
                  style: const TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}