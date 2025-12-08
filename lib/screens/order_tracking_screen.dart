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
import 'package:bolt_usta/models/order.dart' as app_order; // ✅ Используем префикс
import 'package:bolt_usta/models/master_profile.dart';
import 'package:bolt_usta/screens/chat/chat_screen.dart';

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
  final ReviewService _reviewService = ReviewService();

  StreamSubscription? _masterLocationSubscription;
  LatLng? _masterLocation;

  StreamSubscription<app_order.Order?>? _orderStatusSubscription;
  app_order.Order? _currentOrder;

  MasterProfile? _masterProfile;
  GoogleMapController? _mapController;

  final String _defaultMasterName = 'Axtarılır...';

  Timer? _searchTimeoutTimer;
  int _searchSeconds = 0;
  bool _isTimeout = false;
  static const int TIMEOUT_SECONDS = 60;

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
    _searchTimeoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _searchSeconds++);

      if (_searchSeconds >= TIMEOUT_SECONDS) {
        timer.cancel();
        setState(() => _isTimeout = true);
      }
    });
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
      debugPrint('Error fetching master profile: $e');
    }
  }

  void _subscribeToMasterLocation(String mId) {
    _masterLocationSubscription?.cancel();
    _masterLocationSubscription = _firestore
        .collection('users')
        .doc(mId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists || !mounted) return;
      final data = snapshot.data();
      final GeoPoint? geoPoint = data?['lastLocation'] as GeoPoint?;
      if (geoPoint != null) {
        setState(() {
          _masterLocation = LatLng(geoPoint.latitude, geoPoint.longitude);
        });
      }
    });
  }

  void _subscribeToOrder() {
    // ✅ ЯВНО УКАЗЫВАЕМ ТИП АРГУМЕНТА (app_order.Order?)
    _orderStatusSubscription = _orderService.getActiveOrderStream(widget.orderId).listen((app_order.Order? order) {
      if (order == null || !mounted) return;

      if (_masterProfile == null && order.masterId != null) {
        _searchTimeoutTimer?.cancel();
        setState(() => _isTimeout = false);
        _fetchMasterData(order.masterId!);
        _subscribeToMasterLocation(order.masterId!);
      }

      setState(() {
        _currentOrder = order;
      });

      if (order.status == AppConstants.orderStatusCompleted) {
        _showRatingDialog(order.customerId);
      }
    });
  }

  String _getStatusText(app_order.Order order) {
    if (order.status == AppConstants.orderStatusArrived) return "Usta Çatdı";
    if (order.type == app_order.OrderType.scheduled) {
      return "Gözlənilir";
    }
    if (order.status == AppConstants.orderStatusAccepted) return "Yoldadır";
    return "Gözləmədə";
  }

  Color _getStatusColor(app_order.Order order) {
    if (order.status == AppConstants.orderStatusArrived) return Colors.purple;
    if (order.type == app_order.OrderType.scheduled) return Colors.orange;
    return kPrimaryColor;
  }

  Future<void> _cancelOrder() async {
    final bool? confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Sifarişi ləğv et?"),
        content: const Text("Əminsinizmi?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Xeyr")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Bəli", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      await _orderService.clientCancelOrder(widget.orderId);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _callMaster() async {
    if (_masterProfile?.phoneNumber != null) {
      final Uri launchUri = Uri(scheme: 'tel', path: _masterProfile!.phoneNumber);
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      }
    }
  }

  void _openChat() {
    if (_masterProfile != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            chatId: widget.orderId,
            otherUserId: _masterProfile!.uid,
            otherUserName: _masterProfile!.fullName,
          ),
        ),
      );
    }
  }

  Set<Marker> _getMarkers() {
    final markers = <Marker>{};
    markers.add(
      Marker(
        markerId: const MarkerId('clientLocation'),
        position: widget.clientLocation,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
    );
    if (_masterLocation != null) {
      markers.add(
        Marker(
          markerId: const MarkerId('masterLocation'),
          position: _masterLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: InfoWindow(title: _masterProfile?.fullName ?? 'Usta'),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final isPending = _currentOrder?.status == AppConstants.orderStatusPending;
    final isCancelled = _currentOrder?.status == AppConstants.orderStatusCancelled;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _currentOrder?.category ?? 'Cari Sifariş',
            style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
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
                      const Text("Usta axtarılır...", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor)),
                      const SizedBox(height: 5),
                      Text("${TIMEOUT_SECONDS - _searchSeconds} saniyə qaldı", style: const TextStyle(color: Colors.grey)),
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

          if (_isTimeout && isPending)
            _buildTimeoutUI(),

          if (!isPending && !isCancelled && _masterProfile != null)
            Positioned(
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.grey[200],
                            child: const Icon(Icons.person, size: 30, color: Colors.grey),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_masterProfile!.fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.star, color: Colors.amber, size: 16),
                                    Text(" ${_masterProfile!.rating}", style: const TextStyle(fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: _getStatusColor(_currentOrder!).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _getStatusText(_currentOrder!),
                              style: TextStyle(
                                  color: _getStatusColor(_currentOrder!),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13
                              ),
                            ),
                          ),
                        ],
                      ),

                      if (_currentOrder != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: kBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text("Sifariş vaxtı:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                  Text(
                                    DateFormat('dd.MM.yyyy HH:mm').format(_currentOrder!.createdAt),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: kDarkColor, fontSize: 13),
                                  ),
                                ],
                              ),
                              if (_currentOrder!.type == app_order.OrderType.scheduled && _currentOrder!.scheduledTime != null) ...[
                                const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Divider(height: 1, color: Colors.grey)),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text("Planlaşdırılıb:", style: TextStyle(color: Colors.grey, fontSize: 13)),
                                    Text(
                                      DateFormat('dd.MM.yyyy HH:mm').format(_currentOrder!.scheduledTime!),
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimaryColor, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ]
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.phone, color: Colors.white),
                              label: const Text("Zəng"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: kPrimaryColor,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: _callMaster,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.chat_bubble, color: Colors.white),
                              label: const Text("Mesaj"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blueAccent,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onPressed: _openChat,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _cancelOrder,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: kErrorColor),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text("Sifarişi Ləğv Et", style: TextStyle(color: kErrorColor, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeoutUI() {
    return Container(
      color: Colors.white,
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sentiment_dissatisfied, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text("Təəssüf ki, heç kim tapılmadı", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () {
              _orderService.clientCancelOrder(widget.orderId);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryColor),
            child: const Text("BAĞLA", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _showRatingDialog(String customerId) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text("İş tamamlandı!"),
          content: const Text("Zəhmət olmasa ustanı qiymətləndirin."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              child: const Text("Bağla"),
            )
          ],
        ),
      );
    });
  }
}