import 'package:flutter/material.dart';
import 'package:bolt_usta/services/review_service.dart';
// import 'package:bolt_usta/screens/client/customer_home_screen.dart'; // Перенаправление после отзыва

class ReviewFormScreen extends StatefulWidget {
  // Экран может вызываться из трех мест, но для сохранения логики требуется
  // masterId и orderId (если отзыв по заказу)
  final String masterId;
  final String customerId;
  final String? orderId; // Nullable, если отзыв оставлен не через завершенный заказ

  const ReviewFormScreen({
    required this.masterId,
    required this.customerId,
    this.orderId,
    super.key,
  });

  @override
  State<ReviewFormScreen> createState() => _ReviewFormScreenState();
}

class _ReviewFormScreenState extends State<ReviewFormScreen> {
  final ReviewService _reviewService = ReviewService();
  final TextEditingController _reviewController = TextEditingController();
  int _selectedRating = 0; // Reytinq (1-5 звезд)
  bool _isLoading = false;

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  // Логика кнопки "Rəy Bildir"
  Future<void> _submitReview() async {
    if (_selectedRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zəhmət olmasa, qiymət seçin (1-5 ulduz).')), // Пожалуйста, выберите оценку
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Сохраняет новый документ в коллекции Reviews
      await _reviewService.submitReview(
        orderId: widget.orderId ?? 'N/A', // Если orderId не передан, используем заглушку
        customerId: widget.customerId,
        masterId: widget.masterId,
        rating: _selectedRating,
        reviewText: _reviewController.text.trim(),
      );

      // 2. Обновляет средний рейтинг Мастера в коллекции Masters (происходит через Cloud Function)

      // 3. Уведомление и закрытие
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rəyiniz uğurla göndərildi. Reytinq yenilənir.')), // Ваш отзыв успешно отправлен. Рейтинг обновляется.
        );

        // В реальном проекте: Возвращение на Главный экран или Историю Заказов
        // Navigator.of(context).popUntil((route) => route.isFirst);
        Navigator.pop(context);
      }
    } catch (e) {
      print('Ошибка при отправке отзыва: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Xəta baş verdi, cəhd edin.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Rəy Bildir')), // Оставить Отзыв
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ustanın işini necə qiymətləndirirsiniz?', // Как Вы оцениваете работу мастера?
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // -----------------------------------------------------------
            // 1. Оценка "Reytinq" (1-5 звезд)
            // -----------------------------------------------------------
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final ratingValue = index + 1;
                  return IconButton(
                    icon: Icon(
                      ratingValue <= _selectedRating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 40,
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedRating = ratingValue;
                      });
                    },
                  );
                }),
              ),
            ),
            const SizedBox(height: 30),

            // -----------------------------------------------------------
            // 2. Поле "Rəy" (Текстовое поле для отзыва)
            // -----------------------------------------------------------
            const Text(
              'Əlavə Rəy (Отзыв):',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _reviewController,
              decoration: const InputDecoration(
                hintText: 'Ustanın işi haqqında fikirlərinizi yazın...', // Напишите ваше мнение о работе мастера...
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
              maxLines: 5,
            ),

            const SizedBox(height: 50),

            // -----------------------------------------------------------
            // 3. Кнопка "Rəy Bildir"
            // -----------------------------------------------------------
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _submitReview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                  'Rəy Bildir', // Оставить Отзыв
                  style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}