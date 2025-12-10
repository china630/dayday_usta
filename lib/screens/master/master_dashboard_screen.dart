import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/core/app_colors.dart';
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/services/auth_service.dart';
import 'package:bolt_usta/services/master_service.dart';
import 'package:bolt_usta/services/logger_service.dart';
import 'package:bolt_usta/managers/location_manager.dart';

import 'package:bolt_usta/screens/master/profile_editor_screen.dart';
import 'package:bolt_usta/screens/master/master_order_history_screen.dart';
import 'package:bolt_usta/screens/master/modals/accept_order_modal.dart';
import 'package:bolt_usta/screens/auth/auth_screen.dart';
import 'package:bolt_usta/screens/master/master_verification_screen.dart';
import 'package:bolt_usta/screens/debug/debug_log_screen.dart';

enum StatPeriod { today, week, month, allTime }

class MasterDashboardScreen extends StatefulWidget {
  final String masterId;
  final MasterProfile masterProfile;

  const MasterDashboardScreen({
    Key? key,
    required this.masterId,
    required this.masterProfile,
  }) : super(key: key);

  @override
  State<MasterDashboardScreen> createState() => _MasterDashboardScreenState();
}

class _MasterDashboardScreenState extends State<MasterDashboardScreen> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final MasterService _masterService = MasterService();

  late LocationManager _locationManager;
  MasterProfile? _currentProfile;

  int _currentIndex = 0;
  int _debugTapCount = 0;

  StatPeriod _selectedPeriod = StatPeriod.today;
  Map<String, int> _stats = {'emergency': 0, 'scheduled': 0, 'cancelled': 0};

  StreamSubscription<DocumentSnapshot>? _profileSubscription;
  StreamSubscription<QuerySnapshot>? _incomingOrdersSubscription;

  // ✅ 1. ID заказа, который сейчас открыт в модальном окне (чтобы скрыть оверлей)
  String? _currentlyShowingOrderId;

  // ✅ 2. Список заказов, которые мастер отклонил (нажал крестик/отмена)
  final Set<String> _ignoredOrderIds = {};

  bool get isOnline {
    if (_currentProfile == null) return false;
    return _currentProfile!.status != AppConstants.masterStatusUnavailable;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _currentProfile = widget.masterProfile;
    _locationManager = Provider.of<LocationManager>(context, listen: false);
    _initLocationManager();
    _calculateStats();
    _startProfileListening();

    if (isOnline) {
      _startListeningForOrders();
    }

    _checkInitialMessage();

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      Log.i("OPENED FROM BACKGROUND: ${message.data}", "FCM");
      if (message.data.containsKey('orderId')) {
        _handleNotificationOpen(message.data['orderId']);
      }
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      Log.i("FOREGROUND PUSH: ${message.notification?.title}", "FCM");
      if (message.data.containsKey('orderId')) {
        print("Order ID received via Push: ${message.data['orderId']}");
      }
    });
  }

  Future<void> _initLocationManager() async {
    await _locationManager.init(widget.masterId);
    if (isOnline) {
      _locationManager.startTracking();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _profileSubscription?.cancel();
    _incomingOrdersSubscription?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // ЛОГИКА
  // ---------------------------------------------------------------------------

  void _startProfileListening() {
    _profileSubscription?.cancel();
    _profileSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.masterId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data() as Map<String, dynamic>;
        data['uid'] = widget.masterId;
        final updatedProfile = MasterProfile.fromFirestore(data);

        final bool wasOnline = isOnline;
        setState(() => _currentProfile = updatedProfile);
        final bool nowOnline = isOnline;

        if (nowOnline && !wasOnline) {
          _locationManager.startTracking();
          _startListeningForOrders();
        } else if (!nowOnline && wasOnline) {
          _locationManager.stopTracking();
          _incomingOrdersSubscription?.cancel();
          _incomingOrdersSubscription = null;
        }
      }
    });
  }

  void _startListeningForOrders() {
    _incomingOrdersSubscription?.cancel();
    Log.i("Запуск прослушивания заказов...", "OrdersListener");

    _incomingOrdersSubscription = FirebaseFirestore.instance.collection('orders')
        .where('status', isEqualTo: AppConstants.orderStatusPending)
        .snapshots()
        .listen((snapshot) {

      Log.i("Получен снэпшот: ${snapshot.docs.length} документов", "OrdersListener");

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final orderId = doc.id;

        // ✅ Пропускаем отклоненные заказы
        if (_ignoredOrderIds.contains(orderId)) continue;

        final type = data['type'];
        final category = data['category'];
        final targetMasterId = data['targetMasterId'];

        bool shouldNotify = false;

        // 1. Прямой заказ (Срочный или Плановый)
        if (targetMasterId == widget.masterId) {
          shouldNotify = true;
          Log.i("🔔 Прямой заказ найден: $orderId");
        }
        // 2. Срочный или Плановый общий заказ
        else if (targetMasterId == null && (type == 'emergency' || type == 'scheduled')) {
          if (_currentProfile != null && _currentProfile!.categories.contains(category)) {
            shouldNotify = true;
            Log.i("🔔 Общий заказ ($type) найден: $orderId");
          }
        }

        // 🛑 УБРАЛИ АВТО-ОТКРЫТИЕ ОКНА
        // Теперь окно открывается ТОЛЬКО по нажатию кнопки в шторке.
        if (shouldNotify) {
          // Можно добавить звук/вибрацию здесь
        }
      }
    },
        onError: (error) {
          Log.e("КРИТИЧЕСКАЯ ОШИБКА СТРИМА ЗАКАЗОВ!", error);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Ошибка связи: $error"),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 10),
                  action: SnackBarAction(label: "Повторить", onPressed: _startListeningForOrders),
                )
            );
          }
        });
  }

  Future<void> _checkInitialMessage() async {
    await Future.delayed(const Duration(milliseconds: 500));
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null && initialMessage.data.containsKey('orderId')) {
      _handleNotificationOpen(initialMessage.data['orderId']);
    }
  }

  // ✅ Метод для открытия окна (вызывается кнопкой "BAX")
  Future<void> _handleNotificationOpen(String orderId) async {
    if (_currentlyShowingOrderId == orderId) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('orders').doc(orderId).get();
      if (!doc.exists) return;

      final data = doc.data()!;
      if (data['status'] != AppConstants.orderStatusPending) return;

      final clientLoc = data['clientLocation'] as GeoPoint;
      final category = data['category'] ?? '';
      final isEmergency = data['type'] == 'emergency';

      double dist = 0.0;
      try { dist = _calculateDistance(clientLoc); } catch (_) {}

      if (mounted) {
        // 1. Скрываем шторку
        setState(() {
          _currentlyShowingOrderId = orderId;
        });

        // 2. Открываем окно
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          isDismissible: false,
          enableDrag: false,
          builder: (_) => AcceptOrderModal(
            orderId: orderId,
            clientLocation: LatLng(clientLoc.latitude, clientLoc.longitude),
            distanceKm: dist,
            category: category,
            isEmergency: isEmergency,
          ),
        );

        // 3. Возвращаем шторку (если заказ не был принят)
        if (mounted) {
          setState(() {
            _currentlyShowingOrderId = null;
          });
        }
      }
    } catch (e) {
      debugPrint("Error opening modal: $e");
      if(mounted) {
        setState(() => _currentlyShowingOrderId = null);
      }
    }
  }

  // ✅ Метод для кнопки "IMTINA" (Добавляет в игнор)
  void _ignoreOrder(String orderId) {
    setState(() {
      _ignoredOrderIds.add(orderId);
    });
  }

  Future<void> _toggleStatus(bool value) async {
    try {
      await _masterService.toggleMasterStatus(widget.masterId, value);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Səhv: $e")));
    }
  }

  void _signOut() async {
    _locationManager.stopTracking();
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthScreen()),
            (route) => false,
      );
    }
  }

  void _onTabTapped(int index) => setState(() => _currentIndex = index);

  double _calculateDistance(GeoPoint clientLoc) {
    final myPos = _locationManager.currentPosition;
    if (myPos == null) return 0.0;
    return Geolocator.distanceBetween(
        myPos.latitude, myPos.longitude,
        clientLoc.latitude, clientLoc.longitude
    ) / 1000;
  }

  String _getPeriodName(StatPeriod period) {
    switch (period) {
      case StatPeriod.today: return "Bu gün";
      case StatPeriod.week: return "Bu həftə";
      case StatPeriod.month: return "Bu ay";
      case StatPeriod.allTime: return "Bütün dövr";
    }
  }

  Future<void> _calculateStats() async {
    final query = FirebaseFirestore.instance.collection('orders')
        .where('masterId', isEqualTo: widget.masterId)
        .where('status', whereIn: [AppConstants.orderStatusCompleted, AppConstants.orderStatusCancelled]);

    final snapshot = await query.get();
    int emergency = 0; int scheduled = 0; int cancelled = 0;
    final now = DateTime.now();
    DateTime? startDate;

    switch (_selectedPeriod) {
      case StatPeriod.today: startDate = DateTime(now.year, now.month, now.day); break;
      case StatPeriod.week: startDate = now.subtract(Duration(days: now.weekday - 1)); startDate = DateTime(startDate.year, startDate.month, startDate.day); break;
      case StatPeriod.month: startDate = DateTime(now.year, now.month, 1); break;
      case StatPeriod.allTime: startDate = null; break;
    }

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final createdAt = (data['createdAt'] as Timestamp).toDate();
      if (startDate != null && createdAt.isBefore(startDate)) continue;

      final status = data['status'];
      final type = data['type'];
      if (status == AppConstants.orderStatusCancelled) cancelled++;
      else if (status == AppConstants.orderStatusCompleted) {
        if (type == 'emergency') emergency++; else scheduled++;
      }
    }

    if (mounted) setState(() => _stats = {'emergency': emergency, 'scheduled': scheduled, 'cancelled': cancelled});
  }

  // ---------------------------------------------------------------------------
  // UI СТРУКТУРА
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_currentProfile?.verificationStatus != AppConstants.verificationVerified) {
      return _buildVerificationBlocker();
    }

    return Scaffold(
      backgroundColor: kBackgroundColor,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          _buildHomeTab(),
          MasterOrderHistoryScreen(masterId: widget.masterId),
          _buildProfileTab(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: _onTabTapped,
            backgroundColor: Colors.white,
            selectedItemColor: kPrimaryColor,
            unselectedItemColor: Colors.grey[400],
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            showUnselectedLabels: true,
            selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), activeIcon: Icon(Icons.dashboard), label: 'İş Paneli'),
              BottomNavigationBarItem(icon: Icon(Icons.history), activeIcon: Icon(Icons.history_edu), label: 'Tarixçə'),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline), activeIcon: Icon(Icons.person), label: 'Profil'),
            ],
          ),
        ),
      ),
    );
  }

  // --- TAB 1: HOME ---
  Widget _buildHomeTab() {
    String statusText = "Ofline";
    String subStatusText = "Sifariş qəbul edilmir";
    Color statusColor = Colors.grey;

    if (isOnline) {
      if (_currentProfile?.status == AppConstants.masterStatusBusy) {
        statusText = "Sifarişdəsiniz";
        subStatusText = "Aktiv sifariş var";
        statusColor = Colors.orange;
      } else {
        statusText = "Siz Xətdəsiniz";
        subStatusText = "Sifarişlər gələ bilər";
        statusColor = kPrimaryColor;
      }
    }

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: const Text('İş Paneli', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 120),
            child: Column(
              children: [
                // Шапка (без изменений)
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                  decoration: const BoxDecoration(
                    color: kPrimaryColor,
                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(30)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              _debugTapCount++;
                              if (_debugTapCount >= 5) {
                                _debugTapCount = 0;
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const DebugLogScreen()));
                              }
                            },
                            child: CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.white,
                              child: const Icon(Icons.person, size: 35, color: Colors.grey),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _currentProfile?.fullName ?? 'Usta',
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.star, color: Colors.amber, size: 16),
                                      const SizedBox(width: 4),
                                      Text(
                                        "${_currentProfile?.rating.toStringAsFixed(1) ?? '5.0'}",
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 5))],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  statusText,
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: statusColor),
                                ),
                                Text(
                                  subStatusText,
                                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                            Transform.scale(
                              scale: 1.2,
                              child: Switch(
                                value: isOnline,
                                activeColor: kPrimaryColor,
                                onChanged: (_currentProfile?.status == AppConstants.masterStatusBusy)
                                    ? null
                                    : _toggleStatus,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Статистика (без изменений)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      _buildStatsHeader(),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          _buildStatCard("Baxış", "${_currentProfile?.viewsCount ?? 0}", Icons.visibility, Colors.blue),
                          const SizedBox(width: 15),
                          _buildStatCard("Saxlanılıb", "${_currentProfile?.savesCount ?? 0}", Icons.bookmark, Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          _buildStatCard("Təcili", "${_stats['emergency']}", Icons.flash_on, Colors.orange),
                          const SizedBox(width: 10),
                          _buildStatCard("Planlı", "${_stats['scheduled']}", Icons.calendar_today, kPrimaryColor),
                          const SizedBox(width: 10),
                          _buildStatCard("Ləğv", "${_stats['cancelled']}", Icons.cancel, Colors.red),
                        ],
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Aktiv Sifarişlər",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                    ),
                  ),
                ),

                SizedBox(
                    height: 100,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.radar, color: isOnline ? kPrimaryColor.withOpacity(0.5) : Colors.grey[300], size: 40),
                          const SizedBox(height: 10),
                          Text(
                            isOnline ? "Sifariş axtarılır..." : "Siz oflaynsınız",
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    )
                ),
              ],
            ),
          ),

          // ✅ ОВЕРЛЕЙ: Передаем все необходимые параметры
          if (isOnline)
            IncomingOrderOverlay(
              masterId: widget.masterId,
              myCategories: _currentProfile?.categories ?? [],
              blockedOrderId: _currentlyShowingOrderId,
              ignoredOrderIds: _ignoredOrderIds,
              onView: _handleNotificationOpen,
              onReject: _ignoreOrder,
            ),
        ],
      ),
    );
  }

  Widget _buildStatsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("Statistika", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<StatPeriod>(
              value: _selectedPeriod,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down, color: kPrimaryColor, size: 20),
              style: const TextStyle(color: kDarkColor, fontWeight: FontWeight.w600, fontSize: 14),
              items: StatPeriod.values.map((StatPeriod period) {
                return DropdownMenuItem<StatPeriod>(value: period, child: Text(_getPeriodName(period)));
              }).toList(),
              onChanged: (StatPeriod? newValue) {
                if (newValue != null) {
                  setState(() => _selectedPeriod = newValue);
                  _calculateStats();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kDarkColor)),
            const SizedBox(height: 4),
            Text(title, style: TextStyle(color: Colors.grey[500], fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  // --- TAB 3: PROFILE ---
  Widget _buildProfileTab() {
    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(title: const Text('Profil', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: kPrimaryColor, foregroundColor: Colors.white, elevation: 0, centerTitle: true, automaticallyImplyLeading: false),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Center(child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kPrimaryColor, width: 2)), child: const CircleAvatar(radius: 50, backgroundColor: Colors.white, child: Icon(Icons.person, size: 60, color: Colors.grey)))),
            const SizedBox(height: 15),
            Text(_currentProfile?.fullName ?? "Usta", style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kDarkColor)),
            Text(_currentProfile?.phoneNumber ?? "", style: const TextStyle(fontSize: 16, color: Colors.grey)),
            const SizedBox(height: 30),
            _buildProfileOption(icon: Icons.edit, text: "Profili Redaktə Et", onTap: () async {
              final freshProfile = await _masterService.getProfileData(widget.masterId);
              if (freshProfile != null) {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileEditorScreen(initialProfile: freshProfile)));
              }
            }),
            _buildProfileOption(icon: Icons.verified_user, text: "Verifikasiya Statusu", onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MasterVerificationScreen(masterId: widget.masterId)))),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, child: TextButton.icon(onPressed: _signOut, icon: const Icon(Icons.logout, color: Colors.red), label: const Text("Hesabdan Çıx", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)), style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), backgroundColor: Colors.red.withOpacity(0.1), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))))),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileOption({required IconData icon, required String text, required VoidCallback onTap}) {
    return Card(margin: const EdgeInsets.only(bottom: 15), elevation: 0, color: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), child: ListTile(leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: kPrimaryColor)), title: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: kDarkColor)), trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey), onTap: onTap));
  }

  Widget _buildVerificationBlocker() {
    return Scaffold(backgroundColor: kBackgroundColor, appBar: AppBar(title: const Text('Profil'), centerTitle: true, actions: [IconButton(icon: const Icon(Icons.logout), onPressed: _signOut)]), body: Center(child: Padding(padding: const EdgeInsets.all(30.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.security, size: 100, color: kPrimaryColor), const SizedBox(height: 30), const Text("Verifikasiya tələb olunur", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const SizedBox(height: 40), SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MasterVerificationScreen(masterId: widget.masterId))), style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor), child: const Text("VERİFİKASİYA KEÇ", style: TextStyle(color: Colors.white))))]))));
  }
}

// =============================================================================
// ВИДЖЕТ ОВЕРЛЕЯ (С КНОПКАМИ И ИГНОРОМ)
// =============================================================================
class IncomingOrderOverlay extends StatelessWidget {
  final String masterId;
  final List<String> myCategories;
  final String? blockedOrderId;
  final Set<String> ignoredOrderIds;
  final Function(String) onView;
  final Function(String) onReject;

  const IncomingOrderOverlay({
    Key? key,
    required this.masterId,
    required this.myCategories,
    this.blockedOrderId,
    required this.ignoredOrderIds,
    required this.onView,
    required this.onReject,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox();

        final myOrders = snapshot.data!.docs.where((doc) {
          // Если заказ открыт в окне или отклонен - не показываем
          if (doc.id == blockedOrderId) return false;
          if (ignoredOrderIds.contains(doc.id)) return false;

          final data = doc.data() as Map<String, dynamic>;
          final orderCategory = data['category'];
          final targetId = data['targetMasterId'];
          final orderType = data['type'];

          if (targetId == masterId) return true;

          // ✅ Теперь показывает и Срочные, и Плановые
          if (targetId == null &&
              (orderType == 'emergency' || orderType == 'scheduled') &&
              myCategories.contains(orderCategory)) {
            return true;
          }

          return false;
        }).toList();

        if (myOrders.isEmpty) return const SizedBox();

        final orderDoc = myOrders.first;
        final orderData = orderDoc.data() as Map<String, dynamic>;

        final clientLoc = orderData['clientLocation'] as GeoPoint;
        final isEmergency = orderData['type'] == 'emergency';
        final orderId = orderDoc.id;

        double distanceKm = 0.0;
        try {
          final myPos = context.read<LocationManager>().currentPosition;
          if (myPos != null) {
            distanceKm = Geolocator.distanceBetween(
                myPos.latitude,
                myPos.longitude,
                clientLoc.latitude,
                clientLoc.longitude) / 1000;
          }
        } catch(e) {
          print("Geo Error: $e");
        }

        final bottomPadding = MediaQuery.of(context).padding.bottom;

        return Positioned(
          bottom: 20 + bottomPadding,
          left: 20,
          right: 20,
          child: Card(
            elevation: 10,
            shadowColor: Colors.black26,
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: isEmergency ? Colors.redAccent : kPrimaryColor, width: 1.5)
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: isEmergency ? Colors.red[50] : Colors.green[50], shape: BoxShape.circle),
                      child: Icon(isEmergency ? Icons.local_fire_department : Icons.calendar_today, color: isEmergency ? Colors.red : kPrimaryColor, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                orderData['targetMasterId'] == masterId ? "ŞƏXSİ SİFARİŞ!" : (isEmergency ? "YENİ TƏCİLİ SİFARİŞ!" : "YENİ PLANLI SİFARİŞ"),
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isEmergency ? Colors.redAccent : kDarkColor)
                            ),
                            const SizedBox(height: 2),
                            Text(isEmergency ? "Təcili reaksiya tələb olunur" : "Planlı iş qrafiki üçün", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ],
                        )
                    )
                  ]),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Xidmət", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(orderData['category'] ?? "Xidmət", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("Məsafə", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          const SizedBox(height: 4),
                          Text("${distanceKm.toStringAsFixed(1)} km", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor)),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: Row(
                      children: [
                        // Кнопка ОТКАЗА
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => onReject(orderId),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Colors.red),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text("İMTİNA ET", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Кнопка ПРОСМОТРА
                        Expanded(
                          child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0
                              ),
                              onPressed: () => onView(orderId),
                              child: const Text("SİFARİŞƏ BAX", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                          ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}