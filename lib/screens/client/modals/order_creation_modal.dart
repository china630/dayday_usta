import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:bolt_usta/models/order.dart';
import 'package:bolt_usta/services/order_service.dart';
import 'package:bolt_usta/core/app_colors.dart'; // ✅ Цвета

class OrderCreationModal extends StatefulWidget {
  final String clientUserId;
  final String category;
  final GeoPoint location;
  final String? targetMasterId;

  // ✅ НОВЫЙ ПАРАМЕТР: Разрешить срочный вызов?
  final bool allowEmergency;

  const OrderCreationModal({
    Key? key,
    required this.clientUserId,
    required this.category,
    required this.location,
    this.targetMasterId,
    this.allowEmergency = true, // По умолчанию разрешено
  }) : super(key: key);

  @override
  State<OrderCreationModal> createState() => _OrderCreationModalState();
}

class _OrderCreationModalState extends State<OrderCreationModal> {
  final OrderService _orderService = OrderService();

  late OrderType _selectedType;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Если срочный вызов запрещен -> сразу ставим Плановый
    if (!widget.allowEmergency) {
      _selectedType = OrderType.scheduled;
    } else {
      _selectedType = OrderType.emergency;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      height: _selectedType == OrderType.scheduled ? 550 : 400,
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
          Text(
            'Xidmət: ${widget.category}',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),

          // ✅ ПЕРЕКЛЮЧАТЕЛЬ (Показываем только если срочный разрешен)
          if (widget.allowEmergency)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  _buildTab('Təcili (Bolt)', OrderType.emergency),
                  _buildTab('Planlı (Vaxt seç)', OrderType.scheduled),
                ],
              ),
            )
          else
          // Если мастеров нет, показываем сообщение
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Yaxınlıqda boş usta yoxdur. Yalnız planlı sifariş mümkündür.",
                      style: TextStyle(fontSize: 13, color: kDarkColor),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          if (_selectedType == OrderType.emergency) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: kPrimaryColor.withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.flash_on, size: 40, color: kPrimaryColor),
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              'Usta dərhal axtarılacaq.\nBiz 10 km radiusda olan boş ustaları xəbərdar edəcəyik.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ] else ...[
            ListTile(
              leading: const Icon(Icons.calendar_today, color: kPrimaryColor),
              title: Text(_selectedDate == null
                  ? 'Tarix seçin'
                  : DateFormat('dd MMM yyyy').format(_selectedDate!)),
              onTap: _pickDate,
              tileColor: kBackgroundColor,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.access_time, color: kPrimaryColor),
              title: Text(_selectedTime == null
                  ? 'Saat seçin (Mütləq)'
                  : _selectedTime!.format(context)),
              onTap: _pickTime,
              tileColor: kBackgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: _selectedTime == null ? const BorderSide(color: Colors.redAccent) : BorderSide.none,
              ),
            ),
          ],

          const Spacer(),

          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submitOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(
                _selectedType == OrderType.emergency ? 'USTA AXTAR' : 'SİFARİŞİ TƏSDİQLƏ',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(String title, OrderType type) {
    final isSelected = _selectedType == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 4)] : [],
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isSelected ? kDarkColor : Colors.grey[600],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: kPrimaryColor,
            colorScheme: ColorScheme.light(primary: kPrimaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            primaryColor: kPrimaryColor,
            colorScheme: ColorScheme.light(primary: kPrimaryColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _submitOrder() async {
    if (_selectedType == OrderType.scheduled) {
      if (_selectedDate == null || _selectedTime == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Zəhmət olmasa tarix və saatı seçin'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final hasActive = await _orderService.hasActiveOrderInCategory(widget.clientUserId, widget.category);

      if (hasActive) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Xəta"),
              content: const Text("Sizin bu kateqoriyada artıq aktiv sifarişiniz var."),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Bağla"))
              ],
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      DateTime? finalScheduledTime;
      if (_selectedType == OrderType.scheduled && _selectedDate != null && _selectedTime != null) {
        finalScheduledTime = DateTime(
          _selectedDate!.year,
          _selectedDate!.month,
          _selectedDate!.day,
          _selectedTime!.hour,
          _selectedTime!.minute,
        );
      }

      final result = await _orderService.createOrder(
        clientUserId: widget.clientUserId,
        category: widget.category,
        location: widget.location,
        type: _selectedType,
        source: widget.targetMasterId != null ? OrderSource.catalogDirect : OrderSource.boltSearch,
        scheduledTime: finalScheduledTime,
        targetMasterId: widget.targetMasterId,
      );

      if (mounted) {
        if (_selectedType == OrderType.scheduled) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Column(
                children: [
                  Icon(Icons.check_circle, color: kPrimaryColor, size: 50),
                  SizedBox(height: 10),
                  Text("Sifariş Göndərildi!", textAlign: TextAlign.center),
                ],
              ),
              content: const Text(
                "Sifarişiniz ustaya göndərildi.\nUsta təsdiqlədikdən sonra sizə bildiriş gələcək.",
                textAlign: TextAlign.center,
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.pop(context, result);
                  },
                  child: const Text("Bağla", style: TextStyle(color: kPrimaryColor)),
                ),
              ],
            ),
          );
        } else {
          Navigator.pop(context, result);
        }
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Səhv baş verdi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}