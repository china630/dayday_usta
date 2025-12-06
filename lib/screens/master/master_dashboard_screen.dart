// lib/screens/master/master_dashboard_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart'; // Для проверки дистанции
import 'package:firebase_messaging/firebase_messaging.dart'; // ✅ Push-уведомления
import 'package:firebase_auth/firebase_auth.dart'; // ✅ Аутентификация
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // ✅ Каналы уведомлений

import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/services/user_profile_service.dart';
import 'package:bolt_usta/managers/location_manager.dart';
import 'package:bolt_usta/services/order_service.dart';

// ✅ ИМПОРТЫ ЭКРАНОВ
import 'package:bolt_usta/screens/master/accept_order_modal.dart';
import 'package:bolt_usta/screens/master/master_active_order_screen.dart';
import 'package:bolt_usta/screens/master/profile_editor_screen.dart';
import 'package:bolt_usta/screens/master/master_verification_screen.dart';

class MasterDashboardScreen extends StatelessWidget {
  final String masterId;
  final MasterProfile masterProfile;

  const MasterDashboardScreen({
    required this.masterId,
    required this.masterProfile,
    super.key
  });

  @override
  Widget build(BuildContext context) {
    return StreamProvider<MasterProfile>(
      create: (_) => UserProfileService().getMasterProfileStream(masterId),
      initialData: masterProfile,
      child: const _MasterDashboardContent(),
    );
  }
}

class _MasterDashboardContent extends StatefulWidget {
  const _MasterDashboardContent();

  @override
  State<_MasterDashboardContent> createState() => _MasterDashboardContentState();
}

class _MasterDashboardContentState extends State<_MasterDashboardContent> {
  final AuthService _authService = AuthService();
  final UserProfileService _profileService = UserProfileService();
  final OrderService _orderService = OrderService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<QuerySnapshot>? _ordersSubscription;
  bool _isShowingRequest = false;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();

    // 1. Настройка уведомлений
    _setupNotifications();

    // 2. ПРОВЕРКА: Если приложение открылось кликом по пушу (из закрытого состояния)
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        _handleNotificationTap(message);
      }
    });

    // 3. Слушаем заказы в реальном времени (Firestore)
    _startListeningForOrders();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 🔥 ЛОГИКА 0: Настройка Уведомлений
  // --------------------------------------------------------------------------
  Future<void> _setupNotifications() async {
    try {
      FirebaseMessaging messaging = FirebaseMessaging.instance;

      // Разрешения
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // Токен
      String? token = await messaging.getToken();
      User? user = FirebaseAuth.instance.currentUser;
      if (user != null && token != null) {
        await _firestore.collection('users').doc(user.uid).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
      }

      // Канал (Android)
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'emergency_orders',
        'Срочные заказы',
        description: 'Уведомления о новых заказах рядом',
        importance: Importance.max,
        playSound: true,
      );

      await _flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      // A. СЛУШАТЕЛЬ (Приложение ОТКРЫТО)
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint("🔔 Foreground Notification: ${message.notification?.title}");

        if (mounted && message.notification != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("${message.notification!.title}\n${message.notification!.body}"),
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 8), // Показываем подольше
              action: SnackBarAction(
                label: 'BAX (Открыть)', // Кнопка действия
                textColor: Colors.white,
                onPressed: () {
                  _handleNotificationTap(message); // <<-- ВРУЧНУЮ ОТКРЫВАЕМ ЗАКАЗ
                },
              ),
            ),
          );
        }
      });

      // B. СЛУШАТЕЛЬ (Приложение СВЕРНУТО и открывается кликом)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint("🔔 App opened from background via notification");
        _handleNotificationTap(message);
      });

    } catch (e) {
      debugPrint("⚠️ Ошибка настройки уведомлений: $e");
    }
  }

  // --------------------------------------------------------------------------
  // 🔥 ЛОГИКА 1: Обработка НАЖАТИЯ на уведомление
  // --------------------------------------------------------------------------
  void _handleNotificationTap(RemoteMessage message) {
    final data = message.data;
    final String? orderId = data['orderId'];

    debugPrint("🚀 TAP HANDLED. OrderID: $orderId");

    if (orderId != null) {
      // Собираем "фейковые" данные заказа из пуша, чтобы показать окно быстрее
      final Map<String, dynamic> orderData = {
        'category': data['category'] ?? 'Sifariş',
      };

      // Парсим координаты, которые пришли строками
      if (data['lat'] != null && data['lng'] != null) {
        double lat = double.tryParse(data['lat'].toString()) ?? 0.0;
        double lng = double.tryParse(data['lng'].toString()) ?? 0.0;

        // Запускаем расчет и показ окна
        _calculateDistanceAndShow(orderId, orderData, lat, lng);
      } else {
        // Если координат нет, открываем с нулевой дистанцией (подгрузится потом)
        _showAcceptDialog(orderId, orderData, 0.0);
      }
    }
  }

  // Вспомогательная функция для расчета перед показом
  Future<void> _calculateDistanceAndShow(String orderId, Map<String, dynamic> orderData, double clientLat, double clientLng) async {
    try {
      Position position = await Geolocator.getCurrentPosition();
      final distanceMeters = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        clientLat, clientLng,
      );
      // Показываем окно
      _showAcceptDialog(orderId, orderData, distanceMeters / 1000);
    } catch (e) {
      // Если ошибка GPS, все равно показываем окно
      _showAcceptDialog(orderId, orderData, 0.0);
    }
  }

  // --------------------------------------------------------------------------
  // 🔥 ЛОГИКА 2: Слушатель Firestore (если приложение просто открыто)
  // --------------------------------------------------------------------------
  void _startListeningForOrders() {
    _ordersSubscription = _firestore
        .collection('orders')
        .where('status', isEqualTo: AppConstants.orderStatusPending)
        .snapshots()
        .listen((snapshot) {

      if (_isShowingRequest) return;
      if (!mounted) return;

      final master = Provider.of<MasterProfile>(context, listen: false);

      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final orderData = change.doc.data() as Map<String, dynamic>;
          final orderId = change.doc.id;

          final orderCategory = orderData['category'] as String?;
          if (master.categories.isNotEmpty && !master.categories.contains(orderCategory)) {
            continue;
          }
          _checkDistanceAndShowModal(orderId, orderData);
        }
      }
    });
  }

  Future<void> _checkDistanceAndShowModal(String orderId, Map<String, dynamic> orderData) async {
    if (!mounted) return;
    final master = Provider.of<MasterProfile>(context, listen: false);

    if (master.status != AppConstants.masterStatusFree) return;

    final GeoPoint? clientGeo = orderData['clientLocation'];
    if (clientGeo == null) return;

    try {
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final distanceMeters = Geolocator.distanceBetween(
        position.latitude, position.longitude,
        clientGeo.latitude, clientGeo.longitude,
      );
      final distanceKm = distanceMeters / 1000;

      if (distanceKm <= 10.0) {
        _showAcceptDialog(orderId, orderData, distanceKm);
      }
    } catch (e) {
      debugPrint("Ошибка GPS: $e");
    }
  }

  // --------------------------------------------------------------------------
  // 🖥️ UI: Показ Модального Окна
  // --------------------------------------------------------------------------
  void _showAcceptDialog(String orderId, Map<String, dynamic> orderData, double distance) async {
    if (_isShowingRequest) return; // Защита от двойного открытия
    setState(() => _isShowingRequest = true);

    final bool? accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AcceptOrderModal(
        orderId: orderId,
        masterId: Provider.of<MasterProfile>(context, listen: false).uid,
        category: orderData['category'] ?? 'Xidmət',
        clientAddress: 'Müştəri yaxınlıqdadır (${distance.toStringAsFixed(1)} km)',
        distanceKm: distance,
      ),
    );

    if (mounted) {
      setState(() => _isShowingRequest = false);
    }

    if (accepted == true) {
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MasterActiveOrderScreen(orderId: orderId),
          ),
        );
      }
    }
  }

  // --------------------------------------------------------------------------
  // 🖥️ UI: Вспомогательные методы
  // --------------------------------------------------------------------------
  void _openProfileEditor(MasterProfile master) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfileEditorScreen(initialProfile: master)),
    );
  }

  void _openVerification() {
    final masterId = Provider.of<MasterProfile>(context, listen: false).uid;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MasterVerificationScreen(masterId: masterId)),
    );
  }

  Future<void> _unlockAvailability(String masterId) async {
    try {
      await _profileService.updateMasterStatus(masterId, AppConstants.masterStatusFree);
      if (mounted) {
        Provider.of<LocationManager>(context, listen: false).toggleOnlineStatus(true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Status yeniləndi.')));
      }
    } catch (e) {
      // ignore
    }
  }

  Future<void> _generateTestData() async {
    await _orderService.generateMasterTestData();
  }

  @override
  Widget build(BuildContext context) {
    final master = Provider.of<MasterProfile>(context);
    final locationManager = Provider.of<LocationManager>(context);

    final isVerified = master.verificationStatus == AppConstants.verificationVerified;
    final isBlockedByRejection = master.status == AppConstants.masterStatusUnavailable;
    final isOnline = locationManager.isOnline;

    void toggleOnline(bool newValue) {
      if (isBlockedByRejection) return;
      locationManager.toggleOnlineStatus(newValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(newValue ? 'Siz ONLAYN-sınız' : 'Siz OFFLAYN-sınız'),
          duration: const Duration(seconds: 1),
        ),
      );
    }

    String getStatusText() {
      if (isBlockedByRejection) return 'BLOKLANIB';
      if (isOnline) return 'ONLINE (Boşdur)';
      if (master.status == AppConstants.masterStatusBusy) return 'MƏŞĞULDUR';
      return 'OFFLINE';
    }

    Color getStatusColor() {
      if (isBlockedByRejection) return Colors.red.shade900;
      if (isOnline) return Colors.green.shade700;
      return Colors.grey.shade600;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usta Paneli', style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: isBlockedByRejection ? Colors.red.shade800 : Colors.blue.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.exit_to_app),
            onPressed: () async {
              _ordersSubscription?.cancel();
              await locationManager.stopOnlineServiceOnSignOut();
              await _authService.signOut();
            },
            tooltip: 'Çıxış',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Профиль
            Row(
              children: [
                const CircleAvatar(radius: 40, child: Icon(Icons.person, size: 40)),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(master.fullName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(isVerified ? Icons.verified_user : Icons.warning_amber, color: isVerified ? Colors.green : Colors.orange, size: 20),
                          const SizedBox(width: 5),
                          Text(isVerified ? 'Təsdiqlənib' : 'Təsdiqlənməyib', style: TextStyle(color: isVerified ? Colors.green.shade700 : Colors.orange, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Статус
            Card(
              elevation: 4,
              color: isBlockedByRejection ? Colors.red.shade100 : (isOnline ? Colors.green.shade50 : Colors.grey.shade100),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(getStatusText(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: getStatusColor())),
                        Switch(value: isOnline && !isBlockedByRejection, onChanged: isBlockedByRejection ? null : toggleOnline, activeColor: Colors.green.shade600),
                      ],
                    ),
                    if (master.consecutiveRejections > 0)
                      Text('❌ İmtina sayı: ${master.consecutiveRejections}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            if (isBlockedByRejection) _buildBlockWarningAndUnlockButton(master),

            // Статистика
            const Text('Statistika:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatisticCard('Baxışlar', master.viewsCount),
                _buildStatisticCard('Zənglər', master.callsCount),
                _buildStatisticCard('Yaddaşda', master.savesCount),
              ],
            ),

            const SizedBox(height: 30),
            ElevatedButton(onPressed: _generateTestData, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade300), child: const Text('⚠️ DEV: Create Test Data')),
            const SizedBox(height: 20),

            // Меню
            ListTile(leading: const Icon(Icons.edit, color: Colors.blue), title: const Text('Profilə düzəliş et'), onTap: () => _openProfileEditor(master), trailing: const Icon(Icons.arrow_forward_ios, size: 18)),
            const Divider(height: 0),
            ListTile(leading: const Icon(Icons.fingerprint, color: Colors.deepOrange), title: const Text('Eyniləşdirmə'), onTap: _openVerification, trailing: const Icon(Icons.arrow_forward_ios, size: 18)),
            const Divider(height: 0),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockWarningAndUnlockButton(MasterProfile master) {
    return Card(
      color: Colors.red.shade50,
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('🛑 HESAB BLOKLANIB', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ElevatedButton(onPressed: () => _unlockAvailability(master.uid), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade600), child: const Text('BLOKU AÇ', style: TextStyle(color: Colors.white))),
          ],
        ),
      ),
    );
  }

  Widget _buildStatisticCard(String title, int count) {
    return Expanded(
      child: Card(
        elevation: 3,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Text(count.toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}