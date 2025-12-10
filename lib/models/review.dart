import 'package:cloud_firestore/cloud_firestore.dart';

class Review {
  final String id;
  final String customerId;
  final double rating;
  final String reviewText; // ✅ Переименовал, чтобы совпадало с вашим UI
  final DateTime date;

  Review({
    required this.id,
    required this.customerId,
    required this.rating,
    required this.reviewText,
    required this.date,
  });

  factory Review.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Review(
      id: doc.id,
      customerId: data['customerId'] ?? '',
      rating: (data['rating'] ?? 0.0).toDouble(),
      reviewText: data['reviewText'] ?? '', // Читаем из базы
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}