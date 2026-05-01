import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:dayday_usta/models/order.dart' as app_order;
import 'package:dayday_usta/core/app_constants.dart';
import 'package:dayday_usta/core/app_colors.dart';
import 'package:dayday_usta/services/order_service.dart';
import 'package:dayday_usta/screens/order_tracking_screen.dart';

class OrderDetailScreen extends StatefulWidget {
  final app_order.Order order;
  final bool isClient;

  const OrderDetailScreen({
    super.key,
    required this.order,
    this.isClient = true,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  final OrderService _orderService = OrderService();
  bool _repeatBusy = false;

  app_order.Order get order => widget.order;

  Future<void> _repeatOrder() async {
    if (_repeatBusy || !widget.isClient) return;
    setState(() => _repeatBusy = true);
    try {
      final r = await _orderService.repeatOrderFromTemplate(
        clientUserId: order.customerId,
        template: order,
      );
      final id = r['orderId'] as String?;
      if (!mounted || id == null || id.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderTrackingScreen(
            orderId: id,
            masterId: null,
            clientLocation: LatLng(order.clientLocation.latitude, order.clientLocation.longitude),
          ),
        ),
      );
    } catch (e) {
      final msg = e is Exception ? e.toString().replaceFirst('Exception: ', '') : '$e';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } finally {
      if (mounted) setState(() => _repeatBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd MMM yyyy, HH:mm').format(order.createdAt);
    final scheduledStr = order.scheduledTime != null
        ? DateFormat('dd MMM yyyy, HH:mm').format(order.scheduledTime!)
        : null;

    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (order.status) {
      case AppConstants.orderStatusCompleted:
        statusText = 'Tamamlanıb';
        statusColor = kPrimaryColor;
        statusIcon = Icons.check_circle;
        break;
      case AppConstants.orderStatusCancelled:
        statusText = 'Ləğv edilib';
        statusColor = kErrorColor;
        statusIcon = Icons.cancel;
        break;
      case AppConstants.orderStatusCanceledByMaster:
        statusText = 'Usta ləğv etdi';
        statusColor = kErrorColor;
        statusIcon = Icons.cancel;
        break;
      case AppConstants.orderStatusPending:
        statusText = 'Gözləmədə';
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_top;
        break;
      default:
        statusText = 'Aktiv';
        statusColor = Colors.blue;
        statusIcon = Icons.run_circle;
    }

    final showRepeat =
        widget.isClient && order.status == AppConstants.orderStatusCompleted;

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: Text('Sifariş #${order.id.substring(0, 4)}'),
        backgroundColor: kBackgroundColor,
        elevation: 0,
        centerTitle: true,
        foregroundColor: kDarkColor,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(statusIcon, color: statusColor, size: 32),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.category,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold, color: kDarkColor)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(statusText,
                              style: TextStyle(
                                  color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text("Məlumat", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  _buildDetailRow(Icons.calendar_today, "Tarix", dateStr),
                  const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                  _buildDetailRow(
                    order.type == app_order.OrderType.emergency ? Icons.flash_on : Icons.event,
                    "Sifariş Növü",
                    order.type == app_order.OrderType.emergency ? "Təcili" : "Planlı (Kataloq)",
                  ),
                  if (scheduledStr != null) ...[
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                    _buildDetailRow(Icons.schedule, "Təyin olunub", scheduledStr, isHighlight: true),
                  ]
                ],
              ),
            ),

            if (showRepeat) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _repeatBusy ? null : _repeatOrder,
                  icon: _repeatBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.replay),
                  label: const Text('Yenidən sifariş'),
                  style: OutlinedButton.styleFrom(foregroundColor: kPrimaryColor, padding: const EdgeInsets.all(16)),
                ),
              ),
            ],

            const SizedBox(height: 24),

            const Text("Ünvan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kDarkColor)),
            const SizedBox(height: 12),
            Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(order.clientLocation.latitude, order.clientLocation.longitude),
                    zoom: 15,
                  ),
                  markers: {
                    Marker(
                      markerId: const MarkerId('orderLoc'),
                      position: LatLng(order.clientLocation.latitude, order.clientLocation.longitude),
                      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    )
                  },
                  liteModeEnabled: true,
                  zoomControlsEnabled: false,
                  scrollGesturesEnabled: false,
                  mapType: MapType.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {bool isHighlight = false}) {
    return Row(
      children: [
        Icon(icon, size: 22, color: Colors.grey[400]),
        const SizedBox(width: 16),
        Text(label, style: TextStyle(fontSize: 15, color: Colors.grey[600], fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isHighlight ? kPrimaryColor : kDarkColor,
          ),
        ),
      ],
    );
  }
}
