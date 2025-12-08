import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:bolt_usta/models/order.dart' as app_order;
import 'package:bolt_usta/core/app_constants.dart';
import 'package:bolt_usta/core/app_colors.dart'; // ✅ Цвета

class OrderDetailScreen extends StatelessWidget {
  final app_order.Order order;
  final bool isClient;

  const OrderDetailScreen({
    super.key,
    required this.order,
    this.isClient = true,
  });

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
        statusText = 'Tamamlanıb'; statusColor = kPrimaryColor; statusIcon = Icons.check_circle; break;
      case AppConstants.orderStatusCancelled:
        statusText = 'Ləğv edilib'; statusColor = kErrorColor; statusIcon = Icons.cancel; break;
      case AppConstants.orderStatusPending:
        statusText = 'Gözləmədə'; statusColor = Colors.orange; statusIcon = Icons.hourglass_top; break;
      default:
        statusText = 'Aktiv'; statusColor = Colors.blue; statusIcon = Icons.run_circle;
    }

    return Scaffold(
      backgroundColor: kBackgroundColor,
      appBar: AppBar(
        title: Text('Sifariş #${order.id.substring(0, 4)}'),
        backgroundColor: kBackgroundColor,
        elevation: 0,
        centerTitle: true,
        foregroundColor: kDarkColor, // Черный текст заголовка
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Главная карточка статуса
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))],
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
                        Text(order.category, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kDarkColor)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 2. Детали
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
                      order.type == app_order.OrderType.emergency ? "Təcili (Bolt)" : "Planlı (Kataloq)"
                  ),
                  if (scheduledStr != null) ...[
                    const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1)),
                    _buildDetailRow(Icons.schedule, "Təyin olunub", scheduledStr, isHighlight: true),
                  ]
                ],
              ),
            ),

            const SizedBox(height: 24),

            // 3. Карта
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
        Text(value, style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: isHighlight ? kPrimaryColor : kDarkColor
        )),
      ],
    );
  }
}