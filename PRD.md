Product Requirements Document (PRD) & Техническое Задание (Т/З)
Проект: DayDay Usta
Платформа: iOS / Android (Flutter)
Backend: Firebase (Firestore, Cloud Functions, Auth, FCM)

**Оглавление**

1. Описание продукта (Product Vision)  
2. Роли пользователей (User Roles)  
3. Функциональные требования  
   **3.1.** Аутентификация и профили  
   **3.2.** Главный экран и геолокация  
   **3.3.** Система заказов (Order State Machine)  
   **3.4.** Финансовое ядро (Billing & Transactions)  
   **3.5.** Инструменты разработчика (Debug)  
   **3.6.** Аудит заказа (Order Audit Trail)  
4. Техническая архитектура  
   **4.1.** Frontend (Flutter) · **4.2.** Backend (Cloud Functions) · **4.3.** Firestore · **4.4.** Security Rules  
5. Ближайшие задачи (Roadmap для Cursor)  
   **5.1.** Post-MVP UX (удержание и доверие)

1. Описание продукта (Product Vision)
DayDay Usta — это мобильный маркетплейс (агрегатор) услуг в формате «Uber для мастеров». Приложение соединяет клиентов, которым нужен срочный или плановый ремонт, с профильными мастерами, находящимися поблизости.

Основные киллер-фичи:

Радарный поиск мастеров по геолокации (Geohash): волны радиуса **3 → 5 → 10 км** (в пределах `system_settings/global.radiusKm`, не шире 10 км продукта) и каскадное повторное оповещение после отказа/таймаута (см. **§3.3**).

Жесткая финансовая система (депозиты, холдирование средств, штрафы).

Строгий контроль статусов мастера (карантин, блокировка при отрицательном балансе).

Два типа заказов в продукте и UI: **Təcili** (срочный, `emergency`) и **Planlı** (запланированный, `scheduled`) — единые подписи с [DESIGN.md §7](DESIGN.md).

Аудит по заказам: подколлекция событий для разборов споров (см. **§3.6**).

2. Роли пользователей (User Roles)
Клиент (Müştəri): Ищет мастеров, создает заказы, оплачивает услуги (наличными или с баланса), оставляет отзывы.

Мастер (Usta): Проходит верификацию, выходит на линию ("Онлайн"), получает пуш-уведомления о заказах рядом, выполняет работу, платит комиссию платформе.

Администратор (Admin): Управляет справочниками (категории, тарифы), верифицирует мастеров, решает спорные ситуации.

3. Функциональные требования (Functional Requirements)
3.1. Аутентификация и Профили
Авторизация: Вход по номеру телефона с OTP-кодом (Firebase Phone Auth).

Профиль Клиента: Имя, Фамилия, Номер телефона, Баланс.

Профиль Мастера: Имя, Фамилия, Номер телефона, Категории услуг (например, Santexnik), Рейтинг (0.0 - 5.0), Статус верификации, Геопозиция, Баланс.

**Серверные операции по профилю мастера (MVP):** поля `verificationStatus`, `verificationDocs` (подача документов), а также инкременты `viewsCount` и `callsCount` **не пишутся напрямую с клиента** в Firestore — только через вызываемые Cloud Functions (`submitMasterVerification`, `incrementMasterEngagement`). Верификация администратором (`verified` / `rejected`) — через callable `adminSetMasterVerification`.

3.2. Главный экран и Геолокация
Клиент: Видит карту с доступными мастерами поблизости (маркеры). Может выбрать категорию (Bottom Sheet / Modal) и создать заказ.

Мастер: Видит свой статус (Онлайн/Офлайн), статистику (просмотры, заказы) и радар ожидания заказов. Локация мастера обновляется в реальном времени и конвертируется в geoHash для быстрого поиска. При остановке трекинга в профиле выставляются `isOnline: false` и служебный статус мастера `free` (значение `offline` в схеме не используется).

3.3. Система заказов (Order State Machine)
Жизненный цикл заказа строго контролируется Cloud Functions: **клиентское приложение не выполняет прямых `update` по полям `status`, финансам заказа и т.п.** Все переходы — через HTTPS callable (`createOrder`, `acceptOrder`, `masterArrived`, `masterCompleteOrder`, `clientCancelOrder`, `masterCancelOrder` и др.).

Статусы заказа:

**pending:** Клиент создал заказ (документ создаётся только сервером в `createOrder`). Сервер ищет мастеров в радиусе (Geohash + FCM) и рассылает Push.

**accepted:** Мастер принял заказ через `acceptOrder`. Заказ закрепляется за ним, баланс мастера холдируется.

**arrived:** Мастер нажал «Я на месте» через `masterArrived` с передачей координат; сервер проверяет расстояние до клиента (не более `arrivalRadiusMeters`, по умолчанию 200 м).

**completed:** Завершение через `masterCompleteOrder` (минимальное время работы, списание комиссии, запись в `transactions`).

**cancelled / canceledByMaster:** Отмена через соответствующие callable; причины и побочные эффекты (штрафы, разморозка) обрабатывает триггер `onOrderStatusChange`.

**Отмена при отсутствии мастеров:** если после радара некому отправить уведомление, заказ может быть переведён в `cancelled` с `cancellationReason: 'no_masters_found'`, `cancelledBy: 'system'`.

**Радар и каскад:** при отказе мастера от pending-заказа (`rejectOrder`) или истечении таймаура предложения (`registerMasterTimeout`) его UID попадает в массивы **`declinedMasterIds`** / **`timedOutMasterIds`**; затем **асинхронно** запускается повторный поиск (`scheduleRadarRescan`) без блокировки ответа клиенту. При следующей волне FCM эти UID **исключаются** из рассылки.

**Волны радиуса:** на каждом проходе радара сначала выбираются мастера в кольце до **3 км**; если после фильтрации (категория, онлайн, исключения) некому слать push — расширение до **5 км**, затем до **10 км** (верхняя граница — `min(10, radiusKm)` из настроек).

**Очередь для клиента (`searchMeta`):** пока заказ в **`pending`**, сервер обновляет на документе заказа объект **`searchMeta`**: `mastersFound`, `notifiedCount`, `radiusWaveKm`, `mode`, `lastSearchAt`. Клиент подписывается на **документ заказа** (`snapshots` / `OrderService.getActiveOrderStream`) и показывает ту же вторичную строку, что формируется из `OrderSearchMeta.pendingSubtitleAz`: экраны **`OrderTrackingScreen`**, **`ActiveOrderScreen`**, а также полноэкранный поиск **`OrderSearchScreen`** (`lib/screens/order_search_screen.dart`, вызов `initiateEmergencyOrder` → `createOrder`). Типографика и подписи — см. [DESIGN.md §7](DESIGN.md).

**Отмена мастером после принятия:** при `masterCancelOrder` в документ заказа добавляется UID мастера в **`formerMasterIds`** (история отказов/участия), затем `masterId` сбрасывается. История заказов мастера в приложении учитывает заказы как по `masterId`, так и по `formerMasterIds`.

3.4. Финансовое ядро (Billing & Transactions)
У каждого пользователя (и мастера, и клиента) есть два финансовых поля:

balance: Реальные деньги на счету.

frozenBalance: Замороженные деньги (холд).

Доступные средства = balance - frozenBalance.

Правила списаний:

Регистрация: Бонус 20 AZN новым пользователям.

Комиссия сервиса: Стандартная комиссия (например, 4 AZN). **Стрик по календарному дню (Asia/Baku):** при каждом успешном завершении заказа мастером счётчик дня увеличивается; на **каждом 4-м** завершении за этот день комиссия **0 AZN** (списывается только холд с `frozenBalance`, без списания `balance`). Состояние: поля **`bakuOrderStreakDay`**, **`bakuOrderStreakCount`** в `users/{masterId}`; логика в callable **`masterCompleteOrder`**.

Фейсконтроль: Мастер не может переключиться в статус "Онлайн", если его доступные средства меньше стоимости комиссии (4 AZN).

Холдирование: При принятии заказа у мастера замораживается сумма комиссии.

Штрафы: Отмена заказа мастером без уважительной причины (более 3 раз) или побег с линии ведет к штрафу, сгоранию замороженной суммы и уходу в статус unavailable (Карантин). Поздняя отмена клиентом — штраф клиента.

История платежей: Все изменения баланса строго логируются в коллекцию transactions (сумма, тип: topup, penalty, payment, bonus).

**Тестовое пополнение:** `simulateTopUp` доступно только авторизованному пользователю; пополнение **только своего** `userId`, с ограничением суммы (серверная валидация).

3.5. Инструменты разработчика (Debug)
Секретное меню: Открывается по 5 тапам на аватарку в профиле.

Содержит локальные логи (ошибки, инфо) и кнопку-симулятор пополнения баланса терминалом (+10 AZN вызов Cloud Function simulateTopUp с проверками на сервере).

3.6. Аудит заказа (Order Audit Trail)
Для разборов споров и прозрачности ведётся **событийная лента** в подколлекции **`orders/{orderId}/events`**.

Поля события: `type` (например: `order_created`, `status_changed`, `masters_notified`, `master_declined`, `master_offer_timeout`), `timestamp` (server), `actorId` (nullable), `details` (объект с контекстом: смена статуса, число уведомлённых мастеров и т.д.).

Запись событий выполняется **только с сервера** (Cloud Functions / триггеры). Клиенту разрешено **чтение** событий при участии в заказе (клиент, текущий мастер, целевой мастер, мастер из `formerMasterIds`); запись с клиента запрещена правилами.

4. Техническая Архитектура (Tech Stack)
4.1. Frontend (Flutter)
State Management: Provider.

Навигация: Standard Navigator 2.0 / MaterialPageRoute.

UI/UX: Кастомные модальные окна, BottomNavigationBar, вкладки профиля. Стиль, семантика цветов и согласованные подписи (Təcili / Planlı, строка `searchMeta` на экранах ожидания) — см. **DESIGN.md** (в т.ч. **§7**), токены цветов в `app_colors.dart`.

Ключевые пакеты:

firebase_auth, cloud_firestore, cloud_functions, firebase_messaging.

google_maps_flutter (карта).

geolocator (GPS трекинг).

intl (форматирование валют и дат).

rxdart (композиция стримов, в т.ч. объединённая история заказов мастера).

4.2. Backend (Firebase Cloud Functions - TypeScript)
Вся критичная бизнес-логика и безопасность вынесены на сервер. Клиент **не** создаёт документы заказов в Firestore напрямую и **не** меняет статусы/балансы заказов напрямую.

**Основные callable (примерный перечень):**

createOrder, acceptOrder, rejectOrder, registerMasterTimeout, masterArrived, masterCompleteOrder, clientCancelOrder, masterCancelOrder;

submitMasterVerification, incrementMasterEngagement;

adminSetMasterVerification (действия админа по статусу верификации мастера);

simulateTopUp (ограниченный тестовый сценарий).

**Поиск и FCM:** логика радара в вспомогательных функциях (`_processEmergencyOrder`, `_processScheduledOrder` и каскадный `_runRadarRescan`); при отсутствии кандидатов после фильтрации — отмена заказа с `no_masters_found`.

**Firestore Triggers:**

onUserCreated: Выдача приветственного бонуса.

onOrderStatusChange: Распределение штрафов, разморозки, карантин при смене статуса.

onOrderAuditCreated / onOrderAuditStatusChange: Запись событий аудита (создание заказа, смена статуса).

enforceMasterOnlineRule, onMasterLocationUpdate, checkOfflineProbation — по текущей реализации репозитория.

onNewReview: Пересчёт рейтинга мастера (сервером).

4.3. Структура Базы Данных (Firestore Schema)
users/{userId}

role: 'client' | 'master' | 'admin'

balance: number (double)

frozenBalance: number (double)

status: 'free' | 'busy' | 'unavailable' (для мастеров)

isOnline: boolean (для мастеров)

lastLocation: GeoPoint

geoHash: string (для поиска)

favoriteMasterIds: string[] (только **client** — избранные UID мастеров; см. **§5.1**)

verificationStatus, verificationDocs, viewsCount, callsCount — **изменение согласно §3.1 только через CF / триггеры**, не произвольным клиентским patch.

orders/{orderId}

customerId: string

masterId: string (nullable)

targetMasterId: string (nullable)

formerMasterIds: string[] (UID мастеров, ранее отменивших заказ после принятия; для истории и прав доступа)

declinedMasterIds: string[] (отказ от pending / не принял предложение)

timedOutMasterIds: string[] (истёк таймер предложения)

category: string

type: 'emergency' | 'scheduled'

status: 'pending' | 'accepted' | 'arrived' | 'completed' | 'cancelled' | 'canceledByMaster'

clientLocation: GeoPoint

cancelledBy, cancellationReason — по сценарию отмены

isReviewed: boolean (клиент может обновить только это поле напрямую — см. правила)

searchMeta: object (nullable) — при **pending**: `mastersFound`, `notifiedCount`, `radiusWaveKm`, `mode`, `lastSearchAt`; пишет только сервер (радар)

orders/{orderId}/events/{eventId}

type, timestamp, actorId, details — см. **§3.6**

transactions/{transactionId}

userId: string

amount: number

type: 'bonus' | 'payment' | 'topup' | 'penalty' | 'refund'

description: string

createdAt: Timestamp

system_settings/global

serviceFee: 4.0

arrivalRadiusMeters: 200

clientBonus: 20.0

masterBonus: 20.0

adminWebhookUrl: string (optional) — HTTPS URL для **операционного webhook** (POST JSON); см. **§5.1**

category_metrics/{categoryDocId}

category: string

avgFirstAcceptSeconds: number (скользящее среднее: от `createdAt` заказа до `acceptedAt`)

acceptSampleCount: number

updatedAt: Timestamp — обновляет сервер при **`acceptOrder`**

**Индексы:** для запросов истории мастера по `masterId` + `status` + `createdAt` и по `formerMasterIds` + `status` + `createdAt` заданы в `firestore.indexes.json` (деплой вместе с правилами).

4.4. Security Rules (Firestore Rules)
Пользователи (users): клиент не может менять защищённые поля (в т.ч. balance, frozenBalance, rating, verificationStatus, callsCount, viewsCount и ряд серверных полей). Обычные поля профиля — владелец документа.

Транзакции: только чтение своих записей; запись с клиента запрещена.

Заказы (orders): **создание документа заказа с клиента запрещено**; обновление клиентом — только поле `isReviewed` владельцем заказа (после отзыва). Остальное — только Admin SDK / Functions.

Чтение заказов: клиент — свои; мастер — назначенный, целевой, pending для радара, либо присутствие в `formerMasterIds`.

Подколлекция events: чтение участниками заказа; запись только с сервера.

5. Ближайшие задачи (Roadmap для Cursor)
При старте работы в Cursor, ИИ должен опираться на это ТЗ для следующих задач:

Проведение полного E2E тестирования (от создания до завершения заказа).

Интеграция реального платежного шлюза (Webhook) вместо simulateTopUp.

Доработка интерфейса чата внутри заказа (orders/{orderId}/messages).

Создание панели Администратора (Admin Panel) для модерации мастеров — **каркас Flutter Web и MVP** описаны в **[docs/ADMIN_WEB_MVP.md](docs/ADMIN_WEB_MVP.md)**; локальный запуск web-admin: `flutter run -d chrome --target=lib/main_admin.dart`.

**Реализовано в продукте (см. §3.3–3.4):** волны радара 3 / 5 / 10 км, `searchMeta` для клиента, стрик комиссии по дню (Баку). Дальнейшие усиления — по отдельным задачам.

### 5.1. Post-MVP UX (удержание и доверие)

Цель — сделать продукт **понятнее и спокойнее** для клиента и **честнее и выгоднее ощущаться** для мастера, без обязательной привязки к новым CF в первой итерации.

**Клиент (Müştəri)**

- **Прозрачность радара:** при расширении зоны поиска (волна **свыше 3 км**) показывать короткую подсказку в духе «radius genişləndi» рядом с текстом из `searchMeta` (см. **DESIGN.md §7**).
- **Ожидание без тревоги:** таймер/подсказка на экране поиска (Təcili / Planlı); **среднее время первого accept** по категории — коллекция **`category_metrics`**, подсказка в UI (`PendingClientSearchSubtitle`, см. **DESIGN.md §7**).
- **Повтор заказа:** кнопка **«Yenidən sifariş»** — `OrderService.repeatOrderFromTemplate` → `createOrder` (тот же ünvan, kateqoriya, növ; **catalogDirect** + `targetMasterId`, если исходный заказ был с прямым ustadan).
- **Избранные ustalar:** поле **`favoriteMasterIds`** в `users/{clientId}` (правила: правка только у **client**), UI — сердце в **Usta Profili**, полоса **Seçilmiş ustalar** в **Kataloq**; повтор с **catalogDirect** при избранном сценарии поддерживается через повтор заказа.

**Мастер (Usta)**

- **Смена в цифрах:** на главной панели — **выплаченная комиссия за календарный день** (агрегат по `transactions`, тип `payment`) + уже существующий стрик «4-cü sifariş — komissiya 0» (см. §3.4).
- **Микро-празднование стрика:** после `masterCompleteOrder`, если ответ CF содержит `freeCommission: true` — Snackbar или диалог (отдельно от лога в `transactions`).
- **Паспорт заказа до accept:** в модалке предложения — кратко: məsafə, kateqoriya, müştərinin zonası (без лишних данных).

**Доверие и операции**

- **Социальное доказательство:** в карточке мастера для клиента — **verified + sayı tamamlanmış sifariş** (поля с сервера / CF).
- **Споры без тяжёлой админки на старте:** **HTTPS webhook** (`system_settings/global.adminWebhookUrl`): POST JSON при **`submitMasterVerification`** (`master_verification_pending`) и при аудите **`master_declined`** / **`master_offer_timeout`** (см. **§3.6**).

**Статус внедрения (актуально):**

- Клиент: подсказка радара **> 3 км**; **среднее время accept** по категории в строке ожидания; **повтор заказа** — `Sifarişlərim` / **Sifariş detalı**; **избранные ustalar** — Kataloq + профиль ustası.
- Мастер: **«Bu gün ödənilmiş komissiya»**; **SnackBar** при **freeCommission** после `masterCompleteOrder`.
- Сервер: **`category_metrics`**; **webhook** (настраиваемый URL, без URL вызовов нет).
- **В бэклоге:** паспорт заказа в модалке accept; verified + счётчик завершённых в карточке ustası; отдельный таймер «nə baş verir»; расширение webhook на другие типы аудита.

**Памятка продакшена (не забыть): webhook → Telegram**

- В **prod** задать в Firestore **`system_settings/global`** поле **`adminWebhookUrl`**: **HTTPS** URL вашего приёмника, который принимает **POST JSON** от Cloud Functions (`notifyAdminWebhook` в `functions`) и **дублирует алерт в Telegram** (обычно это отдельный короткий HTTPS handler — ещё одна CF, Cloud Run, VPS, n8n — внутри вызов **Telegram Bot API** `sendMessage`; «голого» URL от Telegram под наш JSON нет, нужна эта прослойка).
- Пока поле **пустое или не `https://`** — webhook **не вызывается** (нормально для dev/stage).
- При выкатке фичи в прод: **`firebase deploy --only firestore:rules,functions`** (или ваш стандартный деплой), чтобы правила и функции совпадали с репозиторием.
