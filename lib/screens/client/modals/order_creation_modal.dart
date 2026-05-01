import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:dayday_usta/models/order.dart';
import 'package:dayday_usta/services/order_service.dart';
import 'package:dayday_usta/core/app_colors.dart';

class OrderCreationModal extends StatefulWidget {
  final String clientUserId;
  final String category;
  final GeoPoint location;
  final String? targetMasterId;
  final bool allowEmergency;

  const OrderCreationModal({
    Key? key,
    required this.clientUserId,
    required this.category,
    required this.location,
    this.targetMasterId,
    this.allowEmergency = true,
  }) : super(key: key);

  @override
  State<OrderCreationModal> createState() => _OrderCreationModalState();
}

class _OrderCreationModalState extends State<OrderCreationModal> with SingleTickerProviderStateMixin {
  final OrderService _orderService = OrderService();
  late TabController _tabController;

  bool _isLoading = false;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.allowEmergency ? 2 : 1, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _submitOrder() async {
    final bool isEmergency = widget.allowEmergency && _tabController.index == 0;
    final OrderType selectedType = isEmergency ? OrderType.emergency : OrderType.scheduled;

    if (!isEmergency && (_selectedDate == null || _selectedTime == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zəhmət olmasa tarix və saatı seçin'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final hasActive = await _orderService.hasActiveOrderInCategory(widget.clientUserId, widget.category);
      if (hasActive) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Bu kateqoriyada aktiv sifarişiniz var.")),
          );
        }
        return;
      }

      DateTime? finalScheduledTime;
      if (!isEmergency) {
        finalScheduledTime = DateTime(
          _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
          _selectedTime!.hour, _selectedTime!.minute,
        );
      }

      final result = await _orderService.createOrder(
        clientUserId: widget.clientUserId,
        category: widget.category,
        location: widget.location,
        type: selectedType,
        source: widget.targetMasterId != null ? OrderSource.catalogDirect : OrderSource.radarSearch,
        scheduledTime: finalScheduledTime,
        targetMasterId: widget.targetMasterId,
      );

      if (mounted) {
        if (isEmergency) {
          Navigator.pop(context, {'orderId': result['orderId'], 'mode': 'emergency'});
        } else {
          _showSuccessDialog(result);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Xəta: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog(dynamic result) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.check_circle, color: kPrimaryColor, size: 60),
            SizedBox(height: 15),
            Text("Sifariş Qəbul Edildi!", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
            SizedBox(height: 10),
            Text("Usta təsdiqlədikdən sonra bildiriş alacaqsınız.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context, result);
            },
            child: const Text("BAĞLA", style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: kPrimaryColor)), child: child!),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context, initialTime: TimeOfDay.now(),
      builder: (context, child) => Theme(data: ThemeData.light().copyWith(colorScheme: const ColorScheme.light(primary: kPrimaryColor)), child: child!),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    // 🛠️ FIX: Получаем высоту системного отступа снизу (кнопки Android или полоска iOS)
    final mq = MediaQuery.of(context);
    final bottomPadding = mq.viewPadding.bottom + mq.viewInsets.bottom;
    final maxH = mq.size.height * 0.92;
    final totalHeight = (520.0 + bottomPadding).clamp(0.0, maxH);

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomPadding),
      height: totalHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sifariş Təsdiqi',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kDarkColor),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 5),
          Text('Xidmət: ${widget.category}', style: TextStyle(color: Colors.grey[600]), textAlign: TextAlign.center),
          const SizedBox(height: 25),

          if (widget.allowEmergency)
            Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(25),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(25),
                  color: kPrimaryColor,
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))],
                ),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.grey[600],
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                tabs: const [
                  Tab(text: "TƏCİLİ (İndi)"),
                  Tab(text: "PLANLI (Sonra)"),
                ],
                onTap: (index) => setState(() {}),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(child: Text("Yaxınlıqda boş usta yoxdur. Yalnız planlı sifariş mümkündür.", style: TextStyle(fontSize: 13, color: kDarkColor))),
                ],
              ),
            ),

          const SizedBox(height: 25),

          Expanded(
            child: widget.allowEmergency
                ? TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildEmergencyBody(),
                _buildScheduledBody(),
              ],
            )
                : _buildScheduledBody(),
          ),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                (_widgetIsEmergency()) ? 'USTA AXTAR' : 'SİFARİŞİ TƏSDİQLƏ',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _widgetIsEmergency() {
    return widget.allowEmergency && _tabController.index == 0;
  }

  Widget _buildEmergencyBody() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(25),
          decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.flash_on, size: 50, color: kPrimaryColor),
        ),
        const SizedBox(height: 20),
        const Text(
          'Usta dərhal axtarılacaq.\nCavab gözləmə vaxtı: 60 saniyə.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
        ),
      ],
    );
  }

  Widget _buildScheduledBody() {
    return SingleChildScrollView(
      child: Column(
      children: [
        _buildSelectionTile(
          icon: Icons.calendar_today,
          text: _selectedDate == null ? 'Tarix seçin' : DateFormat('dd MMM yyyy').format(_selectedDate!),
          onTap: _pickDate,
          isSelected: _selectedDate != null,
        ),
        const SizedBox(height: 15),
        _buildSelectionTile(
          icon: Icons.access_time,
          text: _selectedTime == null ? 'Saat seçin' : _selectedTime!.format(context),
          onTap: _pickTime,
          isSelected: _selectedTime != null,
        ),
      ],
    ),
    );
  }

  Widget _buildSelectionTile({required IconData icon, required String text, required VoidCallback onTap, required bool isSelected}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: kBackgroundColor,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: isSelected ? kPrimaryColor : Colors.transparent),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? kPrimaryColor : Colors.grey),
            const SizedBox(width: 15),
            Text(text, style: TextStyle(fontSize: 16, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: kDarkColor)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}