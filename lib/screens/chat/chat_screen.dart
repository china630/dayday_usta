import 'package:flutter/material.dart';
import 'package:bolt_usta/models/chat_message.dart';
import 'package:bolt_usta/services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final String orderId;
  final String currentUserId;
  final String recipientName; // Имя собеседника

  const ChatScreen({
    required this.orderId,
    required this.currentUserId,
    required this.recipientName,
    super.key,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ChatService _chatService = ChatService();
  final TextEditingController _messageController = TextEditingController();

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  // Действие: Отправить сообщение
  void _sendMessage() {
    if (_messageController.text.trim().isNotEmpty) {
      _chatService.sendMessage(
        orderId: widget.orderId,
        senderId: widget.currentUserId,
        text: _messageController.text.trim(),
      );
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Söhbət: ${widget.recipientName}')), // Чат: Имя Собеседника
      body: Column(
        children: [
          // 1. Список Сообщений (StreamBuilder)
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: _chatService.getMessagesStream(widget.orderId),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Mesajlar yüklənmədi.')); // Сообщения не загружены
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text('Hələ heç bir mesaj yoxdur.')); // Нет сообщений
                }

                final messages = snapshot.data!.reversed.toList(); // Обратный порядок для отображения снизу вверх

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 15),
                  itemCount: messages.length,
                  reverse: true, // Начинаем с конца (последние сообщения внизу)
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isCurrentUser = message.senderId == widget.currentUserId;
                    return _buildMessageBubble(message, isCurrentUser);
                  },
                );
              },
            ),
          ),

          // 2. Поле ввода Сообщения
          _buildMessageInput(),
        ],
      ),
    );
  }

  // Виджет для отображения пузырька сообщения
  Widget _buildMessageBubble(ChatMessage message, bool isCurrentUser) {
    return Align(
      alignment: isCurrentUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isCurrentUser ? Colors.blue.shade600 : Colors.grey.shade300,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(12),
            topRight: const Radius.circular(12),
            bottomLeft: Radius.circular(isCurrentUser ? 12 : 0),
            bottomRight: Radius.circular(isCurrentUser ? 0 : 12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(color: isCurrentUser ? Colors.white : Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 10,
                color: isCurrentUser ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Виджет для поля ввода
  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Mesaj yazın...', // Напишите сообщение...
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 10),
              ),
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.send, color: Colors.blue),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}