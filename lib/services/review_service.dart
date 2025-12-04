import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/models/review.dart'; // Предполагаем, что модель Review существует

class ReviewService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _reviewsCollection = 'reviews';
  final String _usersCollection = 'users'; // Для доступа к профилям мастеров

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

    // В этот момент должен сработать Cloud Function 'updateMasterAverageRating()'
    print('Отзыв успешно сохранен. Cloud Function запустит пересчет рейтинга для Мастера $masterId.');
  }

  // --------------------------------------------------------------------------
  // 2. ПОЛУЧЕНИЕ ОТЗЫВОВ
  // --------------------------------------------------------------------------

  // Метод ReviewService: getMasterReviewsStream
  // Получает поток отзывов для отображения на экране 'Usta Profili'
  Stream<List<Review>> getMasterReviewsStream(String masterId) {
    return _db.collection(_reviewsCollection)
        .where('masterId', isEqualTo: masterId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Review.fromFirestore(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    });
  }
}