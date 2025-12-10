import 'package:flutter/material.dart';
import 'package:bolt_usta/core/app_colors.dart';
import 'package:bolt_usta/services/review_service.dart';

class RateMasterModal extends StatefulWidget {
  final String orderId;
  final String masterId;
  final String customerId;

  const RateMasterModal({
    super.key,
    required this.orderId,
    required this.masterId,
    required this.customerId,
  });

  @override
  State<RateMasterModal> createState() => _RateMasterModalState();
}

class _RateMasterModalState extends State<RateMasterModal> {
  final ReviewService _reviewService = ReviewService();
  final TextEditingController _commentController = TextEditingController();

  double _rating = 5.0;
  bool _isLoading = false;

  Future<void> _submit() async {
    setState(() => _isLoading = true);
    try {
      await _reviewService.submitReview(
        orderId: widget.orderId,
        masterId: widget.masterId,
        customerId: widget.customerId,
        rating: _rating,
        comment: _commentController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Təşəkkürlər! Rəyiniz qeydə alındı.")),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Xəta: $e")));
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      // ✅ ИСПРАВЛЕНО: mainAxisSize убрано из Container
      child: Column(
        mainAxisSize: MainAxisSize.min, // ✅ Перенесено сюда
        children: [
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)),
          ),
          const SizedBox(height: 20),
          const Text("İş tamamlandı!", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kDarkColor)),
          const SizedBox(height: 10),
          const Text("Ustanın işini qiymətləndirin", style: TextStyle(color: Colors.grey, fontSize: 16)),

          const SizedBox(height: 20),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              return IconButton(
                iconSize: 40,
                icon: Icon(
                  index < _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                onPressed: () {
                  setState(() => _rating = index + 1.0);
                },
              );
            }),
          ),

          const SizedBox(height: 20),

          TextField(
            controller: _commentController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: "Rəyiniz (könüllü)...",
              filled: true,
              fillColor: kBackgroundColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimaryColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("GÖNDƏR", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}