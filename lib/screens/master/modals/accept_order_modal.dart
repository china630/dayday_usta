import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:dayday_usta/core/app_colors.dart';

class AcceptOrderModal extends StatefulWidget {
  final String orderId;
  final LatLng clientLocation;
  final double distanceKm;
  final String category;
  final bool isEmergency;

  const AcceptOrderModal({
    Key? key,
    required this.orderId,
    required this.clientLocation,
    required this.distanceKm,
    required this.category,
    required this.isEmergency,
  }) : super(key: key);

  @override
  State<AcceptOrderModal> createState() => _AcceptOrderModalState();
}

class _AcceptOrderModalState extends State<AcceptOrderModal> {
  late int _timeLeft;
  late int _totalTime;
  late Timer _timer;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // ✅ Таймер: 15 секунд (срочный) или 15 минут (плановый)
    _totalTime = widget.isEmergency ? 15 : 900;
    _timeLeft = _totalTime;
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeLeft > 0) {
        setState(() => _timeLeft--);
      } else {
        _timer.cancel();
        Navigator.pop(context); // Время вышло
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  Future<void> _acceptOrder() async {
    setState(() => _isLoading = true);
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'europe-west3')
          .httpsCallable('acceptOrder')
          .call({'orderId': widget.orderId});

      if (result.data['success'] == true) {
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Xəta: $e"), backgroundColor: Colors.red),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    final minutes = (_timeLeft / 60).floor();
    final seconds = _timeLeft % 60;
    final timeString = widget.isEmergency
        ? "$seconds saniyə"
        : "${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}";

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(height: 6, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(3))),
              AnimatedContainer(
                duration: const Duration(seconds: 1),
                height: 6,
                width: MediaQuery.of(context).size.width * (_timeLeft / _totalTime),
                decoration: BoxDecoration(color: widget.isEmergency ? Colors.red : kPrimaryColor, borderRadius: BorderRadius.circular(3)),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Text(
            "Qəbul etmək üçün: $timeString",
            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 15),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.isEmergency ? Icons.local_fire_department : Icons.calendar_today, color: widget.isEmergency ? Colors.orange : kPrimaryColor, size: 28),
              const SizedBox(width: 8),
              Text(
                widget.isEmergency ? "YENİ TƏCİLİ SİFARİŞ!" : "YENİ PLANLI SİFARİŞ",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: widget.isEmergency ? Colors.orange : kPrimaryColor),
              ),
            ],
          ),
          const SizedBox(height: 30),

          // Детали
          _buildDetailRow(Icons.category, "Xidmət:", widget.category),
          const SizedBox(height: 15),
          _buildDetailRow(Icons.location_on, "Məsafə:", "${widget.distanceKm.toStringAsFixed(1)} km sizdən aralı"),

          const SizedBox(height: 40),

          // Кнопки
          if (_isLoading)
            const CircularProgressIndicator(color: kPrimaryColor)
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("İMTİNA ET", style: TextStyle(color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _acceptOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text("QƏBUL ET", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(children: [
      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle), child: Icon(icon, color: Colors.black87, size: 24)),
      const SizedBox(width: 15),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)), const SizedBox(height: 2), Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87))])
    ]);
  }
}