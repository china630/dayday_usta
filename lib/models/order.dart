import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/core/app_constants.dart';

// Модель Заказа (Sifariş) [cite: 7]
class Order {
  final String id;
  final String customerId;
  final String category; // Kateqoriya [cite: 67]
  final String problemDescription; // Problemin Qısa Təsviri [cite: 67]
  final GeoPoint clientLocation; // Гео-локация клиента [cite: 68]
  final String status; // 'pending', 'accepted', 'arrived', 'completed', 'cancelled' [cite: 33-37]
  final String? masterId; // ID мастера, принявшего заказ
  final DateTime createdAt;

  Order({
    required this.id,
    required this.customerId,
    required this.category,
    required this.problemDescription,
    required this.clientLocation,
    required this.createdAt,
    this.status = AppConstants.orderStatusPending,
    this.masterId,
  });

  factory Order.fromFirestore(Map<String, dynamic> data, String id) {
    Timestamp ts = data['createdAt'] ?? Timestamp.now();

    return Order(
      id: id,
      customerId: data['customerId'] ?? '',
      category: data['category'] ?? '',
      problemDescription: data['problemDescription'] ?? '',
      clientLocation: data['clientLocation'] is GeoPoint ? data['clientLocation'] : const GeoPoint(0, 0),
      status: data['status'] ?? AppConstants.orderStatusPending,
      masterId: data['masterId'],
      createdAt: ts.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'customerId': customerId,
      'category': category,
      'problemDescription': problemDescription,
      'clientLocation': clientLocation,
      'status': status,
      'masterId': masterId,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}