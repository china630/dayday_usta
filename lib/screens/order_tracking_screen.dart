import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/services/review_service.dart';
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/core/app_colors.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/screens/chat/chat_screen.dart';
import 'package:bolt_usta/screens/client/modals/rate_master_modal.dart';
import 'package:bolt_usta/screens/client/modals/order_creation_modal.dart';

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String? masterId;
  final LatLng clientLocation;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    this.masterId,
    required this.clientLocation,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final OrderService _orderService = OrderService();

  StreamSubscription? _masterLocationSubscription;
  LatLng? _masterLocation;

  StreamSubscription<app_order.Order?>? _orderStatusSubscription;
  app_order.Order? _currentOrder;

  MasterProfile? _masterProfile;
  GoogleMapController? _mapController;

  Timer? _searchTimeoutTimer;
  int _searchSeconds = 0;
  bool _isTimeout = false;

  // Время ожидания будет определяться динамически
  int get _currentTimeoutLimit {
    if (_currentOrder?.type == 'scheduled') {
      return 900; // 15 минут для плановых
    }
    return 15; // 15 секунд для срочных (по умолчанию)
  }

  @override
  void initState() {
    super.initState();
    if (widget.masterId != null) {
      _fetchMasterData(widget.masterId!);
      _subscribeToMasterLocation(widget.masterId!);
    } else {
      _startSearchTimer();
    }

    _subscribeToOrder();
  }

  @override
  void dispose() {
    _searchTimeoutTimer?.cancel();
    _masterLocationSubscription?.cancel();
    _orderStatusSubscription?.cancel();
    super.dispose();
  }

  void _startSearchTimer() {
    _searchTimeoutTimer?.cancel();
    _searchSeconds = 0;
    _isTimeout = false;

    _searchTimeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;

      setState(() => _searchSeconds++);

      // Проверяем лимит времени
      if (_searchSeconds >= _currentTimeoutLimit) {
        timer.cancel();

        // 🔥 ЛОГИКА ЗАВЕРШЕНИЯ ПОИСКА
        if (_currentOrder?.type == 'scheduled') {
          // 1. ПЛАНОВЫЙ: Авто-отмена и выход
          _handleScheduledTimeout();
        } else {
          // 2. СРОЧНЫЙ: Показываем меню выбора
          setState(() => _isTimeout = true);
        }
      }
    });
  }

  // Логика для планового заказа (Авто-отмена)
  Future<void> _handleScheduledTimeout() async {
    try {
      await _orderService.clientCancelOrder(widget.orderId);
      if (mounted) {
        Navigator.pop(context); // Возвращаемся назад
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Təəssüf ki, seçdiyiniz vaxt üçün usta tapılmadı. Zəhmət olmasa başqa vaxt seçin."),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            )
        );
      }
    } catch (e) {
      print("Error cancelling scheduled order: $e");
    }
  }

  Future<void> _fetchMasterData(String mId) async {
    try {
      final doc = await _firestore.collection('users').doc(mId).get();
      if (doc.exists && mounted) {
        setState(() {
          _masterProfile = MasterProfile.fromFirestore({...doc.data()!, 'uid': doc.id});
        });
      }
    } catch (e) {
      debugPrint('Error: $e');
    }
  }

  void _subscribeToMasterLocation(String mId) {
    _masterLocationSubscription?.cancel();
    _masterLocationSubscription = _firestore.collection('users').doc(mId).snapshots().listen((snapshot) {
      if (!snapshot.exists || !mounted) return;
      final data = snapshot.data();
      final GeoPoint? geoPoint = data?['lastLocation'] as GeoPoint?;
      if (geoPoint != null) {
        setState(() => _masterLocation = LatLng(geoPoint.latitude, geoPoint.longitude));
      }
    });
  }

  void _subscribeToOrder() {
    _orderStatusSubscription = _orderService.getActiveOrderStream(widget.orderId).listen((app_order.Order? order) {
      if (order == null || !mounted) return;

      // Если нашелся мастер (статус сменился)
      if (order.status != AppConstants.orderStatusPending && !order.status.contains('cancel')) {
        _searchTimeoutTimer?.cancel();
        setState(() => _isTimeout = false);
      }

      if (_masterProfile == null && order.masterId != null) {
        _fetchMasterData(order.masterId!);
        _subscribeToMasterLocation(order.masterId!);
      }

      setState(() => _currentOrder = order);

      if (order.status == AppConstants.orderStatusCompleted) {
        _showRatingDialog(order.customerId);
      }
    });
  }

  // --- ДЕЙСТВИЯ ПРИ ТАЙМАУТЕ СРОЧНОГО ЗАКАЗА ---

  Future<void> _retrySearch() async {
    if (_currentOrder == null) return;
    await _orderService.clientCancelOrder(widget.orderId);

    final result = await _orderService.createOrder(
      clientUserId: _currentOrder!.customerId,
      category: _currentOrder!.category,
      location: GeoPoint(widget.clientLocation.latitude, widget.clientLocation.longitude),
      type: app_order.OrderType.emergency,
      source: app_order.OrderSource.boltSearch,
      targetMasterId: null,
    );

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(
            orderId: result['orderId'],
            clientLocation: widget.clientLocation,
          ),
        ),
      );
    }
  }

  Future<void> _switchToScheduled() async {
    if (_currentOrder == null) return;
    await _orderService.clientCancelOrder(widget.orderId);

    if (mounted) {
      Navigator.pop(context);
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => OrderCreationModal(
          clientUserId: _currentOrder!.customerId,
          category: _currentOrder!.category,
          location: GeoPoint(widget.clientLocation.latitude, widget.clientLocation.longitude),
          allowEmergency: true,
        ),
      );
    }
  }

  Future<void> _cancelOrder() async {
    await _orderService.clientCancelOrder(widget.orderId);
    if (mounted) Navigator.pop(context);
  }

  // ... Вспомогательные методы UI ...

  Future<void> _callMaster() async {
    if (_masterProfile?.phoneNumber != null) {
      await launchUrl(Uri(scheme: 'tel', path: _masterProfile!.phoneNumber));
    }
  }

  void _openChat() {
    if (_masterProfile != null) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(chatId: widget.orderId, otherUserId: _masterProfile!.uid, otherUserName: _masterProfile!.fullName)));
    }
  }

  void _showRatingDialog(String customerId) {
    if (!mounted) return;
    if (_masterProfile == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,
      isDismissible: false,
      builder: (ctx) => RateMasterModal(
        orderId: widget.orderId,
        masterId: _masterProfile!.uid,
        customerId: customerId,
      ),
    ).then((_) {
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    });
  }

  Color _getStatusColor(app_order.Order order) {
    if (order.status == AppConstants.orderStatusArrived) return Colors.purple;
    if (order.type == app_order.OrderType.scheduled) return Colors.orange;
    return kPrimaryColor;
  }

  String _getStatusText(app_order.Order order) {
    if (order.status == AppConstants.orderStatusArrived) return "Usta Çatdı";
    if (order.status == AppConstants.orderStatusAccepted) return "Yoldadır";
    return "Gözləmədə";
  }

  Set<Marker> _getMarkers() {
    final markers = <Marker>{};
    markers.add(Marker(markerId: const MarkerId('client'), position: widget.clientLocation, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed)));
    if(_masterLocation != null) markers.add(Marker(markerId: const MarkerId('master'), position: _masterLocation!, icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)));
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final isPending = _currentOrder?.status == AppConstants.orderStatusPending;
    final isCancelled = _currentOrder?.status == AppConstants.orderStatusCancelled;

    // Вычисляем оставшееся время для отображения
    final timeLeft = (_currentTimeoutLimit - _searchSeconds).clamp(0, _currentTimeoutLimit);

    // Форматирование времени (для 15 минут)
    String timeLeftString = "$timeLeft saniyə";
    if (_currentTimeoutLimit > 60) {
      final mins = (timeLeft / 60).floor();
      final secs = timeLeft % 60;
      timeLeftString = "${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}";
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentOrder?.category ?? 'Sifariş', style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _cancelOrder),
      ),
      body: Stack(
        children: [
          GoogleMap(
            mapType: MapType.normal,
            initialCameraPosition: CameraPosition(target: widget.clientLocation, zoom: 15),
            onMapCreated: (c) => _mapController = c,
            markers: _getMarkers(),
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
          ),

          // Карточка поиска (Показываем, пока идет поиск и нет таймаута)
          if (isPending && !_isTimeout)
            Positioned(
              top: 20, left: 20, right: 20,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const LinearProgressIndicator(color: kPrimaryColor, backgroundColor: Colors.grey),
                      const SizedBox(height: 15),
                      Text(
                        _currentOrder?.type == 'scheduled'
                            ? "Planlı sifariş üçün usta axtarılır..."
                            : "Təcili usta axtarılır...",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 5),
                      Text("Gözləmə vaxtı: $timeLeftString", style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 15),
                      TextButton(
                        onPressed: _cancelOrder,
                        child: const Text("LƏĞV ET", style: TextStyle(color: kErrorColor, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                ),
              ),
            ),

          // Экран таймаута (Только для Срочных, плановые выходят сами)
          if (_isTimeout && isPending)
            _buildTimeoutUI(),

          if (!isPending && !isCancelled && _masterProfile != null)
            _buildActiveOrderUI(),
        ],
      ),
    );
  }

  // UI Таймаута (Для срочных заказов)
  Widget _buildTimeoutUI() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
            child: const Icon(Icons.sentiment_dissatisfied, size: 60, color: Colors.grey),
          ),
          const SizedBox(height: 20),
          const Text(
              "Təəssüf ki, heç kim tapılmadı",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kDarkColor),
              textAlign: TextAlign.center
          ),
          const SizedBox(height: 10),
          const Text(
            "Bütün ustalar məşğuldur. Yenidən cəhd edin və ya planlı sifariş yaradın.",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 40),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _retrySearch,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("YENİDƏN AXTAR", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 15),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _switchToScheduled,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: kPrimaryColor),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("PLANLI SİFARİŞ ET", style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 15),

          TextButton(
            onPressed: _cancelOrder,
            child: const Text("Sifarişi ləğv et", style: TextStyle(color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOrderUI() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -5))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.person)),
                  const SizedBox(width: 15),
                  Expanded(child: Text(_masterProfile!.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    color: kPrimaryColor.withOpacity(0.1),
                    child: Text(_getStatusText(_currentOrder!), style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
                  )
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.phone, color: Colors.white), label: const Text("Zəng"), onPressed: _callMaster, style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton.icon(icon: const Icon(Icons.chat, color: Colors.white), label: const Text("Mesaj"), onPressed: _openChat, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue))),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: TextButton(onPressed: _cancelOrder, child: const Text("Ləğv et", style: TextStyle(color: Colors.red))))
            ],
          ),
        ),
      ),
    );
  }
}