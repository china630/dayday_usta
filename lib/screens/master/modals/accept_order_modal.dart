import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/core/app_colors.dart';
import 'package:bolt_usta/screens/master/master_active_order_screen.dart';

class AcceptOrderModal extends StatefulWidget {
  final String orderId;
  final LatLng clientLocation; // ✅ ДОБАВЛЕН ЭТОТ ПАРАМЕТР
  final double distanceKm;
  final String category;
  final bool isEmergency;

  const AcceptOrderModal({
    super.key,
    required this.orderId,
    required this.clientLocation, // ✅ И ЗДЕСЬ
    required this.distanceKm,
    required this.category,
    required this.isEmergency,
  });

  @override
  State<AcceptOrderModal> createState() => _AcceptOrderModalState();
}

class _AcceptOrderModalState extends State<AcceptOrderModal> {
  final OrderService _orderService = OrderService();
  bool _isLoading = false;

  Future<void> _acceptOrder() async {
    setState(() => _isLoading = true);
    try {
      await _orderService.acceptOrder(orderId: widget.orderId);
      if (mounted) {
        Navigator.pop(context); // Закрываем модалку
        // Переходим на экран активного заказа
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => MasterActiveOrderScreen(orderId: widget.orderId)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Xəta: $e")));
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _rejectOrder() async {
    setState(() => _isLoading = true);
    try {
      await _orderService.rejectOrder(orderId: widget.orderId);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Xəta: $e")));
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: 380, // Высота шторки
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Заголовок
          Center(
            child: Container(
              width: 50, height: 5,
              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 20),

          Text(
            widget.isEmergency ? "🔥 YENİ TƏCİLİ SİFARİŞ!" : "📅 YENİ PLANLI SİFARİŞ",
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: widget.isEmergency ? Colors.orange : kPrimaryColor
            ),
          ),
          const SizedBox(height: 20),

          // Информация
          _buildInfoRow(Icons.category, "Xidmət:", widget.category),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.location_on, "Məsafə:", "${widget.distanceKm.toStringAsFixed(1)} km sizdən aralı"),

          if (!widget.isEmergency)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                "Müştəri sizin təsdiqinizi gözləyir.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),

          const Spacer(),

          // Кнопки
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoading ? null : _rejectOrder,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.red),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("İMTİNA ET", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _acceptOrder,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("QƏBUL ET", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
          child: Icon(icon, color: kDarkColor, size: 20),
        ),
        const SizedBox(width: 15),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kDarkColor)),
          ],
        )
      ],
    );
  }
}