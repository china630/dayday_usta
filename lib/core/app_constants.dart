class AppConstants {
  // Роли пользователей
  static const String dbRoleCustomer = 'client';
  static const String dbRoleMaster = 'master';
  static const String dbRoleAdmin = 'admin';

  // ✅ Роли для UI (Названия кнопок) - ВОЗВРАЩАЕМ
  static const String uiRoleCustomer = 'Müştəri';
  static const String uiRoleMaster = 'Usta';

  // Статусы мастера
  static const String masterStatusFree = 'free';
  static const String masterStatusBusy = 'busy';
  static const String masterStatusUnavailable = 'unavailable';

  // Статусы верификации
  static const String verificationPending = 'pending';
  static const String verificationVerified = 'verified';
  static const String verificationRejected = 'rejected';

  // Статусы заказа
  static const String orderStatusPending = 'pending';
  static const String orderStatusAccepted = 'accepted';
  static const String orderStatusArrived = 'arrived';
  static const String orderStatusCompleted = 'completed';
  static const String orderStatusCancelled = 'cancelled';
  /// Отмена мастером (сервер: `canceledByMaster`)
  static const String orderStatusCanceledByMaster = 'canceledByMaster';

  /// Если коллекция `categories` в Firestore пуста или недоступна — минимальный список для UI (срочный вызов и т.п.).
  static const List<String> fallbackServiceCategories = [
    'Santexnik',
    'Elektrik',
    'Klimat',
    'Mebel',
  ];
}