import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/models/chat_message.dart';

class ChatService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _ordersCollection = 'orders';

  // --------------------------------------------------------------------------
  // 1. ПОЛУЧЕНИЕ ПОТОКА СООБЩЕНИЙ
  // --------------------------------------------------------------------------

  // Метод ChatService: getMessagesStream
  // Получает поток сообщений для конкретного заказа
  Stream<List<ChatMessage>> getMessagesStream(String orderId) {
    return _db.collection(_ordersCollection)
        .doc(orderId)
        .collection('messages')
        .orderBy('timestamp', descending: true) // Сортировка по времени
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatMessage.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }

  // --------------------------------------------------------------------------
  // 2. ОТПРАВКА СООБЩЕНИЯ
  // --------------------------------------------------------------------------

  // Метод ChatService: sendMessage
  // Отправляет новое сообщение в под-коллекцию
  Future<void> sendMessage({
    required String orderId,
    required String senderId,
    required String text,
  }) async {
    final newMessage = ChatMessage(
      id: '',
      senderId: senderId,
      text: text,
      createdAt: DateTime.now(),
    );

    await _db.collection(_ordersCollection)
        .doc(orderId)
        .collection('messages')
        .add(newMessage.toFirestore());
  }
}