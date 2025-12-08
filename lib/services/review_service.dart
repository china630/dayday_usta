import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/models/review.dart';

class ReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _reviewsCollection = 'reviews';
  final String _usersCollection = 'users';

  // --------------------------------------------------------------------------
  // 1. ОТПРАВКА ОТЗЫВА (Rəy Bildir)
  // --------------------------------------------------------------------------

  // Метод ReviewService: submitReview
  // Сохраняет новый отзыв в коллекции Reviews
  Future<void> submitReview({
    required String orderId,
    required String customerId,
    required String masterId,
    required int rating, // Оценка звездами (1-5)
    required String reviewText,
  }) async {
    final newReview = Review(
      id: '', // ID будет присвоен Firestore
      orderId: orderId,
      customerId: customerId,
      masterId: masterId,
      rating: rating,
      reviewText: reviewText,
      date: DateTime.now(),
    );

    // 1. Сохранение нового документа в коллекции Reviews
    await _db.collection(_reviewsCollection).add(newReview.toFirestore());

    print('Отзыв успешно сохранен. Cloud Function запустит пересчет рейтинга для Мастера $masterId.');
  }

  // --------------------------------------------------------------------------
  // 2. ПОЛУЧЕНИЕ ОТЗЫВОВ
  // --------------------------------------------------------------------------

  // ✅ ИСПРАВЛЕНО: Переименовали метод в getReviewsForMaster, как требуется в UI
  Stream<List<Review>> getReviewsForMaster(String masterId) {
    return _db.collection(_reviewsCollection)
        .where('masterId', isEqualTo: masterId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Review.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }
}