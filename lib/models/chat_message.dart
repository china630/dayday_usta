import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String text;
  final DateTime createdAt; // ✅ Переименовали timestamp -> createdAt

  ChatMessage({
    required this.id,
    required this.senderId,
    required this.text,
    required this.createdAt,
  });

  factory ChatMessage.fromFirestore(Map<String, dynamic> data, String id) {
    // Безопасное получение времени (если null, берем текущее)
    Timestamp ts = data['createdAt'] ?? data['timestamp'] ?? Timestamp.now();

    return ChatMessage(
      id: id,
      senderId: data['senderId'] ?? '',
      text: data['text'] ?? '',
      createdAt: ts.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'text': text,
      'createdAt': FieldValue.serverTimestamp(), // ✅ Сохраняем как createdAt
    };
  }
}