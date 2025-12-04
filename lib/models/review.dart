import 'package:cloud_firestore/cloud_firestore.dart';

// Модель Отзыва (Rəy)
class Review {
  final String id;
  final String orderId; // ID заказа, к которому относится отзыв (может быть null, если отзыв оставлен не через историю заказа)
  final String customerId;
  final String masterId;
  final int rating; // Оценка (1-5 звезд)
  final String reviewText;
  final DateTime date;

  Review({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.masterId,
    required this.rating,
    required this.reviewText,
    required this.date,
  });

  factory Review.fromFirestore(Map<String, dynamic> data, String id) {
    Timestamp ts = data['date'] ?? Timestamp.now();

    return Review(
      id: id,
      orderId: data['orderId'] ?? '',
      customerId: data['customerId'] ?? '',
      masterId: data['masterId'] ?? '',
      rating: data['rating'] is int ? data['rating'] : 0,
      reviewText: data['reviewText'] ?? '',
      date: ts.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'orderId': orderId,
      'customerId': customerId,
      'masterId': masterId,
      'rating': rating,
      'reviewText': reviewText,
      'date': FieldValue.serverTimestamp(),
    };
  }
}