import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dayday_usta/core/app_constants.dart';

// ✅ Тип заказа: срочный или плановый (по записи)
enum OrderType {
  emergency, // Срочно (сейчас)
  scheduled  // Запланировано
}

// ✅ Источник заказа: радар / каталог (legacy в Firestore: boltSearch)
enum OrderSource {
  radarSearch,
  catalogDirect,
}

/// Метаданные радара (пишет Cloud Function на `pending`).
class OrderSearchMeta {
  final int mastersFound;
  final int notifiedCount;
  final int? radiusWaveKm;
  final String? mode;

  const OrderSearchMeta({
    required this.mastersFound,
    required this.notifiedCount,
    this.radiusWaveKm,
    this.mode,
  });

  static OrderSearchMeta? fromFirestore(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final wave = m['radiusWaveKm'];
    return OrderSearchMeta(
      mastersFound: (m['mastersFound'] as num?)?.toInt() ?? 0,
      notifiedCount: (m['notifiedCount'] as num?)?.toInt() ?? 0,
      radiusWaveKm: wave is num ? wave.toInt() : null,
      mode: m['mode'] as String?,
    );
  }

  /// Строка для клиента во время поиска мастера.
  String pendingSubtitleAz(OrderType type) {
    if (mastersFound <= 0) {
      return type == OrderType.scheduled
          ? 'Uyğun usta axtarılır...'
          : 'Yaxınlıqda uyğun usta axtarılır...';
    }
    final km = radiusWaveKm != null ? ' (~$radiusWaveKm km radius)' : '';
    var line =
        'Ətrafda $mastersFound usta tapıldı$km. $notifiedCount nəfərə bildiriş göndərildi.';
    final wave = radiusWaveKm;
    if (wave != null && wave > 3) {
      line += '\nAxtarış zonası genişləndi (~$wave km).';
    }
    return line;
  }

  /// Доп. строка: среднее время до первого accept по категории (сервер `category_metrics`).
  static String avgFirstAcceptHintAz(double? avgSeconds) {
    if (avgSeconds == null || avgSeconds <= 0) return '';
    if (avgSeconds < 90) {
      return 'Bu kateqoriyada orta ilk cavab: ~${avgSeconds.round()} s';
    }
    final m = (avgSeconds / 60).floor();
    final s = (avgSeconds % 60).round();
    if (s >= 15) {
      return 'Bu kateqoriyada orta ilk cavab: ~$m dəq $s s';
    }
    return 'Bu kateqoriyada orta ilk cavab: ~$m dəq';
  }

  /// Полный подзаголовок поиска: meta + опционально метрика.
  String pendingSearchLinesAz(OrderType type, {double? avgFirstAcceptSeconds}) {
    final base = pendingSubtitleAz(type);
    final hint = OrderSearchMeta.avgFirstAcceptHintAz(avgFirstAcceptSeconds);
    if (hint.isEmpty) return base;
    return '$base\n$hint';
  }
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
  final OrderSearchMeta? searchMeta;

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
    this.source = OrderSource.radarSearch,
    this.searchMeta,
  });

  factory Order.fromFirestore(Map<String, dynamic> data, String id) {
    Timestamp ts = data['createdAt'] ?? Timestamp.now();
    Timestamp? scheduledTs = data['scheduledTime'];

    // Парсинг Enum-ов (защита от null)
    OrderType parsedType = OrderType.emergency;
    if (data['type'] == 'scheduled') parsedType = OrderType.scheduled;

    OrderSource parsedSource = OrderSource.radarSearch;
    final src = data['source'];
    if (src == 'catalogDirect') {
      parsedSource = OrderSource.catalogDirect;
    } else if (src == 'boltSearch' || src == 'radarSearch') {
      parsedSource = OrderSource.radarSearch;
    }

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
      searchMeta: OrderSearchMeta.fromFirestore(data['searchMeta']),
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
      'source': source == OrderSource.catalogDirect ? 'catalogDirect' : 'radarSearch',
    };
  }
}