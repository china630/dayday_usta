import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:bolt_usta/core/app_constants.dart';

// ✅ Тип заказа: Срочный (Bolt) или Плановый (по записи)
enum OrderType {
  emergency, // Срочно (сейчас)
  scheduled  // Запланировано
}

// ✅ Источник заказа: Автопоиск или Прямой выбор из каталога
enum OrderSource {
  boltSearch,   // "Найти любого"
  catalogDirect // "Предложить этому мастеру"
}

// Модель Заказа (Sifariş)
class Order {
  final String id;
  final String customerId;
  final String category; // Kateqoriya
  final String problemDescription; // Problemin Qısa Təsviri
  final GeoPoint clientLocation; // Гео-локация клиента
  final String status; // 'pending', 'accepted', 'arrived', 'completed', 'cancelled'
  final String? masterId; // ID мастера, принявшего заказ
  final DateTime createdAt;

  // ✅ НОВЫЕ ПОЛЯ (из Аудита)
  final OrderType type;           // Тип: Срочно / План
  final DateTime? scheduledTime;  // Время визита (если План)
  final OrderSource source;       // Источник: Поиск / Каталог

  Order({
    required this.id,
    required this.customerId,
    required this.category,
    required this.problemDescription,
    required this.clientLocation,
    required this.createdAt,
    this.status = AppConstants.orderStatusPending,
    this.masterId,
    // Дефолтные значения для обратной совместимости
    this.type = OrderType.emergency,
    this.scheduledTime,
    this.source = OrderSource.boltSearch,
  });

  factory Order.fromFirestore(Map<String, dynamic> data, String id) {
    Timestamp ts = data['createdAt'] ?? Timestamp.now();
    Timestamp? scheduledTs = data['scheduledTime'];

    // Парсинг Enum-ов (защита от null)
    OrderType parsedType = OrderType.emergency;
    if (data['type'] == 'scheduled') parsedType = OrderType.scheduled;

    OrderSource parsedSource = OrderSource.boltSearch;
    if (data['source'] == 'catalogDirect') parsedSource = OrderSource.catalogDirect;

    return Order(
      id: id,
      customerId: data['customerId'] ?? '',
      category: data['category'] ?? '',
      problemDescription: data['problemDescription'] ?? '',
      clientLocation: data['clientLocation'] is GeoPoint ? data['clientLocation'] : const GeoPoint(0, 0),
      status: data['status'] ?? AppConstants.orderStatusPending,
      masterId: data['masterId'],
      createdAt: ts.toDate(),
      // ✅ Инициализация новых полей
      type: parsedType,
      scheduledTime: scheduledTs?.toDate(),
      source: parsedSource,
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
      // ✅ Сохранение новых полей
      'type': type == OrderType.scheduled ? 'scheduled' : 'emergency',
      'scheduledTime': scheduledTime != null ? Timestamp.fromDate(scheduledTime!) : null,
      'source': source == OrderSource.catalogDirect ? 'catalogDirect' : 'boltSearch',
    };
  }
}