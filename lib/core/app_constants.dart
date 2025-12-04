// -----------------------------------------------------------------------------
// CORE CONSTANTS
// -----------------------------------------------------------------------------

class AppConstants {
  // Локализация
  static const String defaultLocale = 'az';
  static const String fallbackLocale = 'ru';

  // Роли Пользователей (ЗНАЧЕНИЕ ДЛЯ UI)
  static const String uiRoleCustomer = 'Müştəri';
  static const String uiRoleMaster = 'Usta';
  static const String uiRoleAdmin = 'Admin';

  // Роли Пользователей [cite: 9]
  static const String dbRoleCustomer = 'client'; // Клиент
  static const String dbRoleMaster = 'master'; // Мастер
  static const String dbRoleAdmin = 'admin'; // Администратор

  // ---------------------------------------------------------------------------
  // MASTER STATUSES [cite: 29]
  // ---------------------------------------------------------------------------

  static const String masterStatusFree = 'free'; // Mövcud (Свободен)
  static const String masterStatusBusy = 'busy'; // Mövcud Deyil (Недоступен)
  static const String masterStatusUnavailable = 'unavailable'; // ⚠️ НОВЫЙ СТАТУС: Заблокирован

  // ---------------------------------------------------------------------------
  // ORDER STATUSES [cite: 32]
  // ---------------------------------------------------------------------------

  static const String orderStatusPending = 'pending'; // В ожидании
  static const String orderStatusAccepted = 'accepted'; // Принят
  static const String orderStatusArrived = 'arrived'; // Прибыл
  static const String orderStatusCompleted = 'completed'; // Завершен
  static const String orderStatusCancelled = 'cancelled'; // Отменен

  // ---------------------------------------------------------------------------
  // VERIFICATION STATUSES [cite: 38]
  // ---------------------------------------------------------------------------

  static const String verificationPending = 'pending';
  static const String verificationVerified = 'verified'; // Eyniləşdirilib (Верифицирован)
  static const String verificationRejected = 'rejected';

  // ---------------------------------------------------------------------------
  // CATEGORIES & DISTRICTS (Для выбора) [cite: 57, 58]
  // ---------------------------------------------------------------------------

  // Категории (Услуги) [cite: 57]
  static const List<String> serviceCategories = [
    'Kondisioner',
    'Soyuducu',
    'Paltaryuyan',
    'Qabyuyan',
    'Kombi',
    // Добавить другие
  ];

  // Районы Баку [cite: 58]
  static const List<String> districts = [
    'Binəqədi rayonu',
    'Qaradağ rayonu',
    'Xəzər rayonu',
    'Səbail rayonu',
    'Sabunçu rayonu',
    'Suraxanı rayonu',
    'Nərimanov rayonu',
    'Nəsimi rayonu',
    'Nizami rayonu',
    'Pirallahı rayonu',
    'Xətai rayonu',
    'Yasamal rayonu',
  ];
}