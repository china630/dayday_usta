import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';

import 'package:dayday_usta/core/app_constants.dart';
import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/models/master_profile.dart';
import 'package:dayday_usta/models/review.dart';
import 'package:dayday_usta/models/order.dart' as app_order;
import 'package:dayday_usta/services/master_service.dart';
import 'package:dayday_usta/services/review_service.dart';
import 'package:dayday_usta/services/order_service.dart';
import 'package:dayday_usta/services/favorites_service.dart';
import 'package:dayday_usta/screens/client/modals/order_creation_modal.dart';

class MasterProfileScreen extends StatefulWidget {
  final String masterId;
  final String currentUserId;

  const MasterProfileScreen({
    Key? key,
    required this.masterId,
    required this.currentUserId,
  }) : super(key: key);

  @override
  State<MasterProfileScreen> createState() => _MasterProfileScreenState();
}

class _MasterProfileScreenState extends State<MasterProfileScreen> {
  final MasterService _masterService = MasterService();
  final ReviewService _reviewService = ReviewService();
  final OrderService _orderService = OrderService();
  final FavoritesService _favoritesService = FavoritesService();

  MasterProfile? _masterProfile;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMasterData();
  }

  Future<void> _loadMasterData() async {
    try {
      final profile = await _masterService.getProfileData(widget.masterId);
      if (mounted) {
        setState(() {
          _masterProfile = profile;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _offerOrder() async {
    if (_masterProfile == null) return;

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      position = Position(longitude: 49.8671, latitude: 40.4093, timestamp: DateTime.now(), accuracy: 0, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0);
    }

    if (!mounted) return;

    final isOnline = _masterProfile!.status == AppConstants.masterStatusFree;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => OrderCreationModal(
        clientUserId: widget.currentUserId,
        category: _masterProfile!.categories.isNotEmpty
            ? _masterProfile!.categories.first
            : 'Ümumi',
        location: GeoPoint(position.latitude, position.longitude),
        targetMasterId: widget.masterId,
        allowEmergency: isOnline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_masterProfile == null) {
      return const Scaffold(body: Center(child: Text("Usta tapılmadı")));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Usta Profili", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          StreamBuilder<List<String>>(
            stream: _favoritesService.favoriteMasterIdsStream(widget.currentUserId),
            builder: (context, snap) {
              final fav = snap.data ?? [];
              final isFav = fav.contains(widget.masterId);
              return IconButton(
                tooltip: 'Seçilmiş ustalar',
                icon: Icon(isFav ? Icons.favorite : Icons.favorite_border),
                onPressed: () async {
                  try {
                    await _favoritesService.setFavorite(
                      widget.currentUserId,
                      widget.masterId,
                      !isFav,
                    );
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('$e')),
                      );
                    }
                  }
                },
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const Divider(height: 1, color: Colors.grey),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Услуги (Xidmətlər)
                  _buildSectionTitle("Xidmətlər"),
                  Wrap(
                    spacing: 8,
                    children: _masterProfile!.categories.map((cat) => Chip(
                      label: Text(cat, style: const TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
                      backgroundColor: kPrimaryColor.withOpacity(0.1),
                      side: BorderSide.none,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    )).toList(),
                  ),

                  const SizedBox(height: 24),

                  // 2. О себе (Haqqında)
                  _buildSectionTitle("Haqqında"),
                  Text(
                    _masterProfile!.achievements.isEmpty ? "Məlumat yoxdur." : _masterProfile!.achievements,
                    style: TextStyle(color: Colors.grey[800], height: 1.4, fontSize: 15),
                  ),

                  const SizedBox(height: 24),

                  // 3. Цены (Qiymət)
                  _buildSectionTitle("Qiymət"),
                  Text(
                    _masterProfile!.priceList.isEmpty ? "Razılaşma yolu ilə" : _masterProfile!.priceList,
                    style: TextStyle(color: Colors.grey[800], fontSize: 15),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.grey),
            _buildReviewsSection(),
            const SizedBox(height: 100),
          ],
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
          ),
          child: StreamBuilder<List<app_order.Order>>(
            stream: _orderService.getClientActiveOrdersStream(widget.currentUserId),
            builder: (context, snapshot) {

              bool isButtonEnabled = true;
              String buttonText = "SİFARİŞ TƏKLİF ET";
              Color buttonColor = kPrimaryColor;

              if (snapshot.hasData) {
                final activeOrders = snapshot.data!;
                final hasPending = activeOrders.any((o) => o.status == AppConstants.orderStatusPending);
                final hasActiveInThisCategory = activeOrders.any((o) =>
                o.status != AppConstants.orderStatusPending &&
                    _masterProfile!.categories.contains(o.category)
                );

                if (hasPending) {
                  isButtonEnabled = false;
                  buttonText = "Gözləmədə olan sifariş var";
                  buttonColor = Colors.grey;
                } else if (hasActiveInThisCategory) {
                  isButtonEnabled = false;
                  buttonText = "Aktiv sifarişiniz var";
                  buttonColor = Colors.grey;
                }
              }

              return SizedBox(
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: isButtonEnabled ? 4 : 0,
                  ),
                  onPressed: isButtonEnabled ? _offerOrder : null,
                  child: Text(
                      buttonText,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor)),
    );
  }

  Widget _buildHeader() {
    final isOnline = _masterProfile!.status == AppConstants.masterStatusFree;

    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: kBackgroundColor,
            child: const Icon(Icons.person, size: 40, color: Colors.grey),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    _masterProfile!.fullName,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: kDarkColor)
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.star, color: Colors.amber, size: 16),
                          const SizedBox(width: 4),
                          Text(
                              _masterProfile!.rating.toStringAsFixed(1),
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.amber, fontSize: 13)
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isOnline ? kPrimaryColor.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: BoxDecoration(
                              color: isOnline ? kPrimaryColor : Colors.grey,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                              isOnline ? "Boşdur (Online)" : "Məşğuldur",
                              style: TextStyle(
                                  color: isOnline ? kPrimaryColor : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13
                              )
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildSectionTitle("Rəylər"),
          StreamBuilder<List<Review>>(
            stream: _reviewService.getReviewsForMaster(widget.masterId),
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(child: Text("Hələ rəy yoxdur.", style: TextStyle(color: Colors.grey))),
                );
              }
              final reviews = snapshot.data!.take(3).toList();
              return Column(children: reviews.map((review) {
                return Card(
                    elevation: 0,
                    color: kBackgroundColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        title: Row(children: List.generate(5, (index) => Icon(index < review.rating ? Icons.star : Icons.star_border, color: Colors.amber, size: 14))),
                        subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              Text(review.reviewText, style: const TextStyle(color: kDarkColor)),
                              const SizedBox(height: 4),
                              Text("${review.date.day}.${review.date.month}.${review.date.year}", style: TextStyle(fontSize: 11, color: Colors.grey[500]))
                            ]
                        )
                    )
                );
              }).toList());
            },
          ),
        ],
      ),
    );
  }
}