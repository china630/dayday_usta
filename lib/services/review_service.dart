import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/models/review.dart'; // ✅ Импортируем модель

class ReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Отправка отзыва
  Future<void> submitReview({
    required String orderId,
    required String masterId,
    required String customerId,
    required double rating,
    required String comment,
  }) async {
    try {
      await _db.collection('reviews').add({
        'orderId': orderId,
        'masterId': masterId,
        'customerId': customerId,
        'rating': rating,
        'reviewText': comment, // В базе поле называется reviewText
        'date': FieldValue.serverTimestamp(),
      });

      // Помечаем заказ как оцененный
      await _db.collection('orders').doc(orderId).update({
        'isReviewed': true,
      });

    } catch (e) {
      print('Error submitting review: $e');
      throw e;
    }
  }

  // Получение отзывов мастера
  Stream<List<Review>> getReviewsForMaster(String masterId) {
    return _db
        .collection('reviews')
        .where('masterId', isEqualTo: masterId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => Review.fromFirestore(doc))
        .toList());
  }
}