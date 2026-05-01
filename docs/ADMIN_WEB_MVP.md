# Flutter Web Admin — MVP и каркас

Связь с продуктом: **[PRD.md](../PRD.md)** (роль Admin §1, верификация §3.1, callable `adminSetMasterVerification`, аудит **§3.6**, `system_settings` **§4.3**).

## Цель MVP

Одна **внутренняя** веб-панель на **Flutter Web** для операторов с ролью `admin`: модерация верификаций, просмотр заказов, **только чтение** аудита по заказу, просмотр глобальных настроек. Без публичного SEO, без клиентского UX.

## Модель доступа

| Слой | Правило |
|------|--------|
| **Firestore Rules** | Доступ к чувствительным коллекциям через `isAdmin()` — профиль `users/{uid}` с полем **`role == 'admin'`** (см. `firestore.rules`). |
| **Callable Functions** | Операции с правами (например `adminSetMasterVerification`) проверяют админа на сервере через **`assertCallerIsAdmin`** по тому же документу пользователя. |
| **Опционально (позже)** | Жёсткий **allowlist UID** в `system_settings/global` или Remote Config + проверка в CF — дополнительный предохранитель, если роль `admin` выдаётся редко и вручную. |
| **Веб-приложение** | После входа **Firebase Auth** загружается профиль из `users/{uid}`; если роль не `admin` — экран отказа и выход. **Не** полагаться только на клиент: Rules + CF обязательны. |

### Ограничения текущих правил (важно для MVP)

- **`system_settings`**: с клиента **`write: false`** — в админке MVP экран настроек **только для чтения**; изменение тарифов/webhook — через **Firebase Console**, скрипт или будущую CF `adminUpdateSystemSettings`.
- **`transactions`**: чтение только «свои» записи по `userId`; **глобальный журнал транзакций для админа в MVP не заложен в Rules** — при необходимости отдельная задача: `allow read: if isAdmin() || ...`.

## Состав MVP (функционально)

1. **Верификации мастеров** — список `users` с `role == master` и `verificationStatus == pending`; карточка мастера; действия **Təsdiqlə** / **İmtina** через существующий **`adminSetMasterVerification`** (`AdminService`). Документы/фото при наличии в `verificationDocs` — отображение по мере готовности полей (без новых CF в MVP).
2. **Заказы** — поток последних заказов (`orders` `orderBy createdAt desc limit N`); переход в деталь заказа (поля заказа read-only для оператора).
3. **Аудит (read-only)** — подколлекция `orders/{orderId}/events`: `type`, `timestamp`, `actorId`, `details` — список без редактирования (см. PRD **§3.6**).
4. **`system_settings/global`** — чтение документа и вывод ключевых полей (`serviceFee`, `arrivalRadiusMeters`, бонусы, `adminWebhookUrl` — URL при желании маскировать в UI).

Вне MVP первой веб-итерации: полноценный справочник категорий/районов с записью, массовые рассылки, глобальный список `transactions`, чат заказа как модерация.

## Структура экранов (IA)

```
AdminWebGate (auth → проверка role)
  └── AdminWebShell (NavigationRail)
        ├── Ana səhifə      — счётчики / краткая сводка (reuse AdminService stats)
        ├── Təsdiqlər       — список pending → push → AdminVerificationScreen (существующий)
        ├── Sifarişlər      — список заказов → push → Order detail + вкладка «Audit»
        └── Parametrlər     — read-only system_settings/global
```

**Деталь заказа:** вкладки или секции «Ümumi» (статус, müştəri, usta, kateqoriya, vaxt) və «Audit hadisələri» (stream `events`).

## Каркас в репозитории

| Путь | Назначение |
|------|------------|
| `lib/main_admin.dart` | Точка входа web-admin: только `Firebase.initializeApp` + `Provider<AuthService>` + `AdminWebApp` (без FCM / локальных уведомлений). |
| `lib/admin_web/admin_web_app.dart` | `MaterialApp`, тема, `home: AdminWebGate`. |
| `lib/admin_web/admin_web_gate.dart` | Поток auth + профиль; только `admin` → `AdminWebShell`. |
| `lib/admin_web/admin_web_shell.dart` | `NavigationRail` + `IndexedStack` по разделам MVP. |
| `lib/admin_web/screens/admin_web_dashboard_screen.dart` | Заглушка/минимальная сводка. |
| `lib/admin_web/screens/admin_web_verifications_screen.dart` | Список pending + переход к верификации. |
| `lib/admin_web/screens/admin_web_orders_screen.dart` | Список заказов. |
| `lib/admin_web/screens/admin_web_order_detail_screen.dart` | Заказ + read-only audit. |
| `lib/admin_web/screens/admin_web_settings_screen.dart` | Read-only `system_settings/global`. |
| `lib/services/admin_service.dart` | Методы `watchRecentOrdersForAdmin`, `watchOrderAuditEvents` (и далее по мере роста). |

## Запуск

```bash
flutter pub get
flutter run -d chrome --target=lib/main_admin.dart
```

Сборка под хостинг:

```bash
flutter build web --target=lib/main_admin.dart
```

Отдельный **Firebase Hosting site** или префикс `/admin` — на усмотрение деплоя; важно ограничить доступ (IP / Basic Auth на CDN / отдельный проект Firebase для staging).

## Следующие шаги (после каркаса)

- Индекс Firestore для `orders` + `createdAt`, если консоль запросит при первом запуске.
- CF для безопасного изменения `system_settings` + правило `allow update: if isAdmin()` при согласовании схемы.
- Allowlist админ-UID и аудит действий админа в `orders/.../events` или отдельной коллекции.
