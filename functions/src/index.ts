import * as admin from "firebase-admin";
import {
    onDocumentCreated,
    onDocumentUpdated,
    Change,
    FirestoreEvent,
    QueryDocumentSnapshot
} from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDistance } from "geolib";
import { geohashQueryBounds, geohashForLocation } from "geofire-common";

// --- КОНСТАНТЫ И НАСТРОЙКИ ---
type LatLng = { latitude: number, longitude: number };

// Дефолтные настройки (если в базе пусто)
const DEFAULTS = {
    SERVICE_FEE: 4.0,           // Цена заказа
    RADIUS_KM: 10,              // Радиус поиска
    ARRIVAL_RADIUS_METERS: 200, // Радиус "Я на месте"
    MIN_WORK_TIME_MINUTES: 5,   // Мин. время работы
    PROBATION_MINUTES: 45,      // Время карантина (мин)
    CLIENT_BONUS: 20.0,         // Бонус клиенту
    MASTER_BONUS: 20.0          // Бонус мастеру
};

setGlobalOptions({ region: "europe-west3", maxInstances: 10 });

if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();

// Коллекции
const USERS_COLLECTION = "users";
const ORDERS_COLLECTION = "orders";
const TRANSACTIONS_COLLECTION = "transactions"; // ✅ НОВАЯ КОЛЛЕКЦИЯ
const SETTINGS_COLLECTION = "system_settings";
const CONFIG_DOC = "global";
const CATEGORY_METRICS_COLLECTION = "category_metrics";

// Статусы
const MASTER_ROLE = "master";
const PENDING_STATUS = "pending";
const ACCEPTED_STATUS = "accepted";
const ARRIVED_STATUS = "arrived";
const COMPLETED_STATUS = "completed";
const CANCELLED_STATUS = "cancelled";
const CANCELED_BY_MASTER_STATUS = "canceledByMaster";
const UNAVAILABLE_STATUS = "unavailable";

// =============================================================================
// 0. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (НАСТРОЙКИ И ЛОГИРОВАНИЕ)
// =============================================================================
async function getGlobalSettings() {
    try {
        const docSnap = await db.collection(SETTINGS_COLLECTION).doc(CONFIG_DOC).get();
        if (docSnap.exists) {
            const data = docSnap.data();
            return {
                serviceFee: Number(data?.serviceFee) || DEFAULTS.SERVICE_FEE,
                radiusKm: Number(data?.radiusKm) || DEFAULTS.RADIUS_KM,
                arrivalRadiusMeters: Number(data?.arrivalRadiusMeters) || DEFAULTS.ARRIVAL_RADIUS_METERS,
                minWorkTimeMinutes: Number(data?.minWorkTimeMinutes) || DEFAULTS.MIN_WORK_TIME_MINUTES,
                probationDurationMs: (Number(data?.probationMinutes) || DEFAULTS.PROBATION_MINUTES) * 60 * 1000,
                clientBonus: (data?.clientBonus !== undefined) ? Number(data.clientBonus) : DEFAULTS.CLIENT_BONUS,
                masterBonus: (data?.masterBonus !== undefined) ? Number(data.masterBonus) : DEFAULTS.MASTER_BONUS,
                adminWebhookUrl: typeof data?.adminWebhookUrl === "string" ? String(data.adminWebhookUrl).trim() : "",
            };
        }
    } catch (e) {
        console.error("⚠️ Failed to fetch settings, using defaults", e);
    }
    return {
        serviceFee: DEFAULTS.SERVICE_FEE,
        radiusKm: DEFAULTS.RADIUS_KM,
        arrivalRadiusMeters: DEFAULTS.ARRIVAL_RADIUS_METERS,
        minWorkTimeMinutes: DEFAULTS.MIN_WORK_TIME_MINUTES,
        probationDurationMs: DEFAULTS.PROBATION_MINUTES * 60 * 1000,
        clientBonus: DEFAULTS.CLIENT_BONUS,
        masterBonus: DEFAULTS.MASTER_BONUS,
        adminWebhookUrl: "",
    };
}

/** Безопасный id документа category_metrics по строке категории. */
function categoryMetricsDocId(category: string): string {
    const c = (category || "").trim().replace(/\//g, "_") || "unknown";
    return c.length > 200 ? c.slice(0, 200) : c;
}

/** Скользящее среднее: время от создания заказа до accept (секунды). */
async function updateCategoryAcceptLatencySeconds(category: string, latencySeconds: number): Promise<void> {
    if (!Number.isFinite(latencySeconds) || latencySeconds < 0 || latencySeconds > 86400 * 7) return;
    const docId = categoryMetricsDocId(category);
    const ref = db.collection(CATEGORY_METRICS_COLLECTION).doc(docId);
    try {
        await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            const n = snap.exists ? Number(snap.get("acceptSampleCount")) || 0 : 0;
            const oldAvg = snap.exists ? Number(snap.get("avgFirstAcceptSeconds")) || 0 : 0;
            const newN = n + 1;
            const newAvg = n === 0 ? latencySeconds : (oldAvg * n + latencySeconds) / newN;
            tx.set(ref, {
                category: (category || "").trim() || "unknown",
                avgFirstAcceptSeconds: newAvg,
                acceptSampleCount: newN,
                updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            }, { merge: true });
        });
    } catch (e) {
        console.error("updateCategoryAcceptLatencySeconds", category, e);
    }
}

/** POST JSON на URL из `system_settings/global.adminWebhookUrl` (https). */
async function notifyAdminWebhook(eventType: string, payload: Record<string, unknown>): Promise<void> {
    const config = await getGlobalSettings();
    const url = (config as { adminWebhookUrl?: string }).adminWebhookUrl;
    if (!url || typeof url !== "string" || !url.startsWith("https://")) return;
    try {
        const res = await fetch(url, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
                event: eventType,
                at: new Date().toISOString(),
                ...payload,
            }),
        });
        if (!res.ok) {
            console.error("notifyAdminWebhook HTTP", res.status, await res.text().catch(() => ""));
        }
    } catch (e) {
        console.error("notifyAdminWebhook failed", eventType, e);
    }
}

// 📜 ✅ НОВАЯ ФУНКЦИЯ: ЗАПИСЬ ЧЕКА В ИСТОРИЮ
async function _logTransaction(userId: string, amount: number, type: string, description: string, orderId: string | null = null) {
    try {
        await db.collection(TRANSACTIONS_COLLECTION).add({
            userId: userId,
            amount: amount,          // +20 или -4
            type: type,              // 'bonus', 'payment', 'topup', 'penalty', 'refund'
            description: description,
            orderId: orderId,
            createdAt: admin.firestore.FieldValue.serverTimestamp()
        });
        console.log(`📝 Transaction logged: ${userId} | ${amount} | ${type}`);
    } catch (e) {
        console.error("Failed to log transaction", e);
    }
}

// =============================================================================
// 0b. AUDIT: orders/{orderId}/events
// =============================================================================

type OrderAuditEventType =
    | "order_created"
    | "status_changed"
    | "masters_notified"
    | "master_declined"
    | "master_offer_timeout";

interface OrderAuditEventInput {
    readonly type: OrderAuditEventType;
    readonly actorId: string | null;
    readonly details: Readonly<Record<string, unknown>>;
}

async function appendOrderEvent(orderId: string, input: OrderAuditEventInput): Promise<void> {
    try {
        await db.collection(ORDERS_COLLECTION).doc(orderId).collection("events").add({
            type: input.type,
            timestamp: admin.firestore.FieldValue.serverTimestamp(),
            actorId: input.actorId,
            details: { ...input.details },
        });
        if (input.type === "master_declined" || input.type === "master_offer_timeout") {
            void notifyAdminWebhook("order_audit", {
                orderId,
                auditType: input.type,
                actorId: input.actorId,
                details: input.details,
            });
        }
    } catch (e) {
        console.error("appendOrderEvent failed", orderId, input.type, e);
    }
}

function inferStatusChangeActor(
    before: admin.firestore.DocumentData,
    after: admin.firestore.DocumentData
): string | null {
    if (after.status === ACCEPTED_STATUS && typeof after.masterId === "string") {
        return after.masterId;
    }
    if (after.cancelledBy === "client" && typeof after.customerId === "string") {
        return after.customerId;
    }
    if (after.cancelledBy === "system") return "system";
    if (after.status === CANCELED_BY_MASTER_STATUS && typeof before.masterId === "string" && before.masterId) {
        return before.masterId;
    }
    if (typeof before.masterId === "string" && before.masterId) return before.masterId;
    if (typeof after.masterId === "string" && after.masterId) return after.masterId;
    if (typeof after.customerId === "string") return after.customerId;
    return null;
}

async function getUserRole(uid: string): Promise<string | null> {
    const u = await db.collection(USERS_COLLECTION).doc(uid).get();
    return u.exists ? (u.get("role") as string | undefined) ?? null : null;
}

async function assertCallerIsAdmin(request: { auth?: { uid: string } | undefined }): Promise<string> {
    if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Auth required");
    const role = await getUserRole(request.auth.uid);
    if (role !== "admin") throw new HttpsError("permission-denied", "Admin only");
    return request.auth.uid;
}

// =============================================================================
// 1. ТРИГГЕРЫ (АВТОМАТИКА)
// =============================================================================

// А. 🎁 Начисление бонуса при регистрации + ЛОГ
exports.onUserCreated = onDocumentCreated("users/{userId}", async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const userData = snap.data();
    const role = userData.role;

    const config = await getGlobalSettings();
    let bonusAmount = 0.0;

    if (role === 'client') {
        bonusAmount = config.clientBonus;
    } else if (role === 'master') {
        bonusAmount = config.masterBonus;
    }

    if (bonusAmount > 0) {
        await snap.ref.update({
            balance: admin.firestore.FieldValue.increment(bonusAmount),
        });
        // 📜 Пишем историю
        await _logTransaction(event.params.userId, bonusAmount, 'bonus', 'Qeydiyyat bonusu');
    }
    return null;
});

// Б. Обновление GeoHash (без изменений)
exports.onMasterLocationUpdate = onDocumentUpdated(
    "users/{userId}",
    async (event: FirestoreEvent<Change<QueryDocumentSnapshot> | undefined, { userId: string }>) => {
        if (!event.data) return null;
        const afterData = event.data.after.data();
        const beforeData = event.data.before.data();

        if (afterData?.status === 'busy' || afterData?.status === UNAVAILABLE_STATUS) return null;
        if (!afterData || !afterData.lastLocation) return null;
        if (afterData.role !== MASTER_ROLE) return null;

        const beforeLoc = beforeData?.lastLocation;
        const afterLoc = afterData.lastLocation;

        if (beforeLoc && beforeLoc.latitude === afterLoc.latitude && beforeLoc.longitude === afterLoc.longitude) {
            return null;
        }

        const hash = geohashForLocation([afterLoc.latitude, afterLoc.longitude]);
        return event.data.after.ref.update({ geoHash: hash });
    }
);

// В. Фейсконтроль (без изменений)
exports.enforceMasterOnlineRule = onDocumentUpdated(
    "users/{userId}",
    async (event: FirestoreEvent<Change<QueryDocumentSnapshot> | undefined, { userId: string }>) => {
        if (!event.data) return null;
        const newData = event.data.after.data();
        const oldData = event.data.before.data();
        if (!newData || !oldData) return null;

        if (oldData.isOnline === false && newData.isOnline === true) {
            const config = await getGlobalSettings();
            const balance = newData.balance || 0;
            const frozen = newData.frozenBalance || 0;
            const available = balance - frozen;

            if (available < config.serviceFee) {
                console.log(`⛔ Master ${event.params.userId} blocked from Online.`);
                return event.data.after.ref.update({
                    isOnline: false,
                    status: UNAVAILABLE_STATUS,
                    lastBlockedAt: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        }
        return null;
    }
);

// Г. Карантин (без изменений)
exports.checkOfflineProbation = onDocumentUpdated("users/{userId}", async (event) => {
    if (!event.data) return null;
    const newData = event.data.after.data();
    const oldData = event.data.before.data();

    if (oldData.isOnline === true && newData.isOnline === false) {
        const now = Date.now();
        const probationTime = newData.probationEndsAt ? newData.probationEndsAt.toMillis() : 0;

        if (now < probationTime) {
            console.log(`🚨 Master ${event.params.userId} escaped probation!`);
            return event.data.after.ref.update({
                isOnline: false,
                status: UNAVAILABLE_STATUS,
                banExpiresAt: admin.firestore.Timestamp.fromMillis(now + 24 * 60 * 60 * 1000),
                probationEndsAt: null
            });
        }
    }
    return null;
});

// Д. Контроль статусов и Финансов (С ЗАПИСЬЮ ИСТОРИИ ШТРАФОВ)
exports.onOrderStatusChange = onDocumentUpdated(
    "orders/{orderId}",
    async (event: FirestoreEvent<Change<QueryDocumentSnapshot> | undefined, { orderId: string }>) => {
        if (!event.data) return null;

        const change = event.data;
        const afterData = change.after.data();
        const beforeData = change.before.data();

        if (!afterData || !beforeData) return null;

        const beforeStatus = beforeData.status;
        const afterStatus = afterData.status;
        const masterId = afterData.masterId || beforeData.masterId;
        const clientId = afterData.customerId;

        if (beforeStatus === afterStatus) return null;

        const config = await getGlobalSettings();
        const FEE = config.serviceFee;
        const PROBATION = config.probationDurationMs;

        const batch = db.batch();
        let batchCommitted = false;

        // --- ЛОГИКА МАСТЕРА ---
        if (masterId) {
            const masterRef = db.collection(USERS_COLLECTION).doc(masterId);
            const masterDoc = await masterRef.get();

            if (masterDoc.exists) {
                const masterData = masterDoc.data();
                let mUpdates: any = {};

                // 1. Мастер освободился
                if ([COMPLETED_STATUS, CANCELLED_STATUS, CANCELED_BY_MASTER_STATUS].includes(afterStatus)) {
                    const currentBalance = masterData?.balance || 0;
                    const currentFrozen = masterData?.frozenBalance || 0;
                    const available = currentBalance - currentFrozen;

                    if (available < FEE) {
                        mUpdates.isOnline = false;
                        mUpdates.status = UNAVAILABLE_STATUS;
                    } else if (masterData?.status !== UNAVAILABLE_STATUS) {
                        mUpdates.status = 'free';
                    }
                }

                // 2. Обработка ОТМЕН
                if (afterStatus === CANCELED_BY_MASTER_STATUS) {
                    const reason = afterData.cancellationReason;

                    if (reason === 'china_combi' || reason === 'problem_not_solvable') {
                        // Легальная отмена -> Возврат заморозки
                        mUpdates.frozenBalance = admin.firestore.FieldValue.increment(-FEE);
                        mUpdates.probationEndsAt = admin.firestore.Timestamp.fromMillis(Date.now() + PROBATION);
                    } else {
                        // Штраф
                        mUpdates.frozenBalance = admin.firestore.FieldValue.increment(-FEE);
                        mUpdates.balance = admin.firestore.FieldValue.increment(-FEE);
                        mUpdates.consecutiveRejections = (masterData?.consecutiveRejections || 0) + 1;
                        if (mUpdates.consecutiveRejections >= 3) {
                            mUpdates.status = UNAVAILABLE_STATUS;
                            mUpdates.isOnline = false;
                        }
                        // 📜 Лог штрафа
                        await _logTransaction(masterId, -FEE, 'penalty', 'Cərimə: Sifarişdən imtina', event.params.orderId);
                    }
                }
                else if (afterStatus === CANCELLED_STATUS) {
                    const reason = afterData.cancellationReason;
                    if (reason === 'fraud_master_asked') {
                        // Штраф
                        mUpdates.frozenBalance = admin.firestore.FieldValue.increment(-FEE);
                        mUpdates.balance = admin.firestore.FieldValue.increment(-FEE);
                        // 📜 Лог штрафа
                        await _logTransaction(masterId, -FEE, 'penalty', 'Cərimə: Müştəri şikayəti', event.params.orderId);
                    } else {
                        // Возврат
                        mUpdates.frozenBalance = admin.firestore.FieldValue.increment(-FEE);
                        mUpdates.probationEndsAt = admin.firestore.Timestamp.fromMillis(Date.now() + PROBATION);
                    }
                }
                else if (afterStatus === ARRIVED_STATUS) {
                    mUpdates.consecutiveRejections = 0;
                }

                if (Object.keys(mUpdates).length > 0) {
                    batch.update(masterRef, mUpdates);
                    batchCommitted = true;
                }
            }
        }

        // --- ЛОГИКА КЛИЕНТА (Штрафы) ---
        if (afterData.type === 'scheduled' && clientId) {
             const clientRef = db.collection(USERS_COLLECTION).doc(clientId);
             if (afterStatus === COMPLETED_STATUS ||
                 (afterStatus === CANCELLED_STATUS && afterData.cancellationReason !== 'late_cancellation') ||
                 afterStatus === CANCELED_BY_MASTER_STATUS) {
                 batch.update(clientRef, { frozenBalance: admin.firestore.FieldValue.increment(-FEE) });
                 batchCommitted = true;
             }
             else if (afterStatus === CANCELLED_STATUS && afterData.cancellationReason === 'late_cancellation') {
                 batch.update(clientRef, {
                     frozenBalance: admin.firestore.FieldValue.increment(-FEE),
                     balance: admin.firestore.FieldValue.increment(-FEE)
                 });
                 batchCommitted = true;
                 // 📜 Лог штрафа
                 await _logTransaction(clientId, -FEE, 'penalty', 'Cərimə: Gecikmiş ləğv', event.params.orderId);
             }
        }

        if (batchCommitted) await batch.commit();
        return null;
    }
);

exports.onOrderAuditCreated = onDocumentCreated("orders/{orderId}", async (event) => {
    const snap = event.data;
    if (!snap) return null;
    const d = snap.data();
    const customerId = typeof d.customerId === "string" ? d.customerId : null;
    await appendOrderEvent(event.params.orderId, {
        type: "order_created",
        actorId: customerId,
        details: {
            category: d.category ?? null,
            orderType: d.type ?? null,
            source: d.source ?? null,
        },
    });
    return null;
});

exports.onOrderAuditStatusChange = onDocumentUpdated("orders/{orderId}", async (event) => {
    if (!event.data) return null;
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!before || !after) return null;
    if (before.status === after.status) return null;
    await appendOrderEvent(event.params.orderId, {
        type: "status_changed",
        actorId: inferStatusChangeActor(before, after),
        details: {
            from: before.status,
            to: after.status,
            cancelledBy: after.cancelledBy ?? null,
        },
    });
    return null;
});

// Е. Обновление рейтинга (без изменений)
exports.onNewReview = onDocumentCreated("reviews/{reviewId}", async (event) => {
    // ... тот же код, что был у тебя ...
    const snap = event.data;
    if (!snap) return null;
    const review = snap.data();
    const masterId = review.masterId;
    const newRating = review.rating;
    if (!masterId || typeof newRating !== 'number') return null;
    const masterRef = db.collection(USERS_COLLECTION).doc(masterId);
    try {
        await db.runTransaction(async (transaction) => {
            const masterDoc = await transaction.get(masterRef);
            if (!masterDoc.exists) return;
            const currentSum = masterDoc.get('totalRatingSum') || 0;
            const currentCount = masterDoc.get('reviewCount') || 0;
            const updatedSum = currentSum + newRating;
            const updatedCount = currentCount + 1;
            const averageRating = updatedCount > 0 ? (updatedSum / updatedCount) : 0;
            transaction.update(masterRef, {
                rating: parseFloat(averageRating.toFixed(1)),
                totalRatingSum: updatedSum,
                reviewCount: updatedCount,
            });
        });
    } catch (e) { console.error(e); }
    return null;
});

// =============================================================================
// 2. ВЫЗЫВАЕМЫЕ ФУНКЦИИ (API)
// =============================================================================

// 1. Создание заказа
exports.createOrder = onCall(async (request) => {
    console.log("🚀 START: createOrder called", request.data);
    const config = await getGlobalSettings();
    const body = request.data ?? {};
    const {
        clientUserId, category, latitude, longitude,
        type = 'emergency',
        scheduledTime = null,
        targetMasterId = null
    } = body;
    const rawSource = body.source;
    let source: string;
    if (rawSource === "catalogDirect") {
        source = "catalogDirect";
    } else if (rawSource === "boltSearch" || rawSource === "radarSearch") {
        source = "radarSearch";
    } else {
        source = "radarSearch";
    }

    if (!clientUserId || !category || !latitude || !longitude) {
        throw new HttpsError('invalid-argument', 'Missing required order data.');
    }

    const clientRef = db.collection(USERS_COLLECTION).doc(clientUserId);
    const clientSnap = await clientRef.get();
    if (!clientSnap.exists) throw new HttpsError('not-found', 'Client not found');

    const clientData = clientSnap.data();
    const cAvailable = (clientData?.balance || 0) - (clientData?.frozenBalance || 0);

    if (cAvailable < config.serviceFee) {
        throw new HttpsError('failed-precondition', 'insufficient-funds-client');
    }

    if (type === 'scheduled') {
        await clientRef.update({
            frozenBalance: admin.firestore.FieldValue.increment(config.serviceFee)
        });
    }

    const orderRef = db.collection(ORDERS_COLLECTION).doc();
    const orderId = orderRef.id;

    const orderData = {
        id: orderId,
        customerId: clientUserId,
        category: category,
        clientLocation: new admin.firestore.GeoPoint(latitude, longitude),
        status: PENDING_STATUS,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        type: type,
        source: source,
        scheduledTime: scheduledTime ? admin.firestore.Timestamp.fromDate(new Date(scheduledTime)) : null,
        masterId: null,
        targetMasterId: targetMasterId,
        formerMasterIds: [] as string[],
        declinedMasterIds: [] as string[],
        timedOutMasterIds: [] as string[],
    };

    await orderRef.set(orderData);

    if (type === 'emergency') {
        return _processEmergencyOrder(orderId, orderData, latitude, longitude, targetMasterId, config);
    } else {
        return _processScheduledOrder(orderId, orderData, latitude, longitude, targetMasterId, config);
    }
});

// 2. Принятие заказа
exports.acceptOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const config = await getGlobalSettings();

    const masterId = request.auth.uid;
    const { orderId } = request.data;

    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const masterRef = db.collection(USERS_COLLECTION).doc(masterId);

    await db.runTransaction(async (t) => {
        const oDoc = await t.get(orderRef);
        const mDoc = await t.get(masterRef);

        if (!oDoc.exists) throw new HttpsError('not-found', 'Order not found');
        if (!mDoc.exists) throw new HttpsError('not-found', 'Master profile not found');

        const orderData = oDoc.data();
        const masterData = mDoc.data();

        if (orderData?.status !== PENDING_STATUS) throw new HttpsError('failed-precondition', 'Order already taken');

        const available = (masterData?.balance || 0) - (masterData?.frozenBalance || 0);
        if (available < config.serviceFee) throw new HttpsError('failed-precondition', 'insufficient-funds');

        t.update(orderRef, {
            status: ACCEPTED_STATUS,
            masterId: masterId,
            acceptedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        t.update(masterRef, {
            status: 'busy',
            frozenBalance: admin.firestore.FieldValue.increment(config.serviceFee)
        });
    });

    const oFinal = await orderRef.get();
    const d = oFinal.data();
    if (d) {
        const createdAt = d.createdAt as admin.firestore.Timestamp | undefined;
        const acceptedAt = d.acceptedAt as admin.firestore.Timestamp | undefined;
        if (createdAt && acceptedAt) {
            const latSec = Math.max(0, (acceptedAt.toMillis() - createdAt.toMillis()) / 1000);
            await updateCategoryAcceptLatencySeconds(String(d.category ?? ""), latSec);
        }
    }

    return { success: true, message: `Order ${orderId} accepted.` };
});

// 3. Мастер Прибыл
exports.masterArrived = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const config = await getGlobalSettings();
    const { orderId, latitude, longitude } = request.data;

    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw new HttpsError('not-found', 'Order not found');
    const orderData = orderSnap.data();

    if (orderData?.status !== ACCEPTED_STATUS) throw new HttpsError('failed-precondition', 'Order status is not accepted');
    if (orderData?.masterId !== request.auth.uid) throw new HttpsError('permission-denied', 'Not assigned master');

    const clientLoc = orderData.clientLocation;
    if (clientLoc && latitude && longitude) {
        const distMeters = getDistance(
            { latitude: latitude, longitude: longitude },
            { latitude: clientLoc.latitude, longitude: clientLoc.longitude }
        );
        if (distMeters > config.arrivalRadiusMeters) {
            throw new HttpsError('out-of-range', `Вы далеко (${distMeters}м).`);
        }
    }

    await orderRef.update({
        status: ARRIVED_STATUS,
        arrivedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    return { success: true };
});

// 4. Мастер Завершил (с оплатой и ЛОГОМ)
exports.masterCompleteOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const config = await getGlobalSettings();
    const orderId = request.data.orderId;
    const masterId = request.auth.uid;

    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const masterRef = db.collection(USERS_COLLECTION).doc(masterId);

    const orderSnap = await orderRef.get();
    const orderData = orderSnap.data();

    if (!orderData) throw new HttpsError('not-found', 'Order not found');
    if (orderData.masterId !== masterId) throw new HttpsError('permission-denied', 'Not assigned master');
    if (orderData.status !== ARRIVED_STATUS) throw new HttpsError('failed-precondition', 'Сначала нажмите "Я на месте"');

    const arrivedAt = orderData.arrivedAt;
    if (arrivedAt) {
        const arrivedDate = arrivedAt.toDate();
        const diffMinutes = (new Date().getTime() - arrivedDate.getTime()) / 1000 / 60;
        if (diffMinutes < config.minWorkTimeMinutes) {
            throw new HttpsError('failed-precondition', `Минимум ${config.minWorkTimeMinutes} мин. работы.`);
        }
    }

    const bakuKey = getBakuDateKey(new Date());
    let freeCommission = false;

    await db.runTransaction(async (t) => {
        const oSnap = await t.get(orderRef);
        const mSnap = await t.get(masterRef);
        if (!oSnap.exists || !mSnap.exists) {
            throw new HttpsError("not-found", "Order or master not found");
        }
        const o = oSnap.data()!;
        const m = mSnap.data()!;
        if (o.masterId !== masterId) {
            throw new HttpsError("permission-denied", "Not assigned master");
        }
        if (o.status !== ARRIVED_STATUS) {
            throw new HttpsError("failed-precondition", "Сначала нажмите \"Я на месте\"");
        }

        let streakDay = typeof m.bakuOrderStreakDay === "string" ? m.bakuOrderStreakDay : "";
        let streakCount = Number(m.bakuOrderStreakCount) || 0;
        if (streakDay !== bakuKey) {
            streakDay = bakuKey;
            streakCount = 0;
        }
        streakCount += 1;
        freeCommission = streakCount > 0 && streakCount % 4 === 0;

        const masterPatch: Record<string, unknown> = {
            bakuOrderStreakDay: streakDay,
            bakuOrderStreakCount: streakCount,
        };
        if (freeCommission) {
            masterPatch.frozenBalance = admin.firestore.FieldValue.increment(-config.serviceFee);
        } else {
            masterPatch.balance = admin.firestore.FieldValue.increment(-config.serviceFee);
            masterPatch.frozenBalance = admin.firestore.FieldValue.increment(-config.serviceFee);
        }

        t.update(masterRef, masterPatch);
        t.update(orderRef, {
            status: COMPLETED_STATUS,
            completedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
    });

    if (freeCommission) {
        await _logTransaction(masterId, 0, "payment", "Komissiya: gün ərzində hər 4-cü sifariş (Bakı UTC+4)", orderId);
    } else {
        await _logTransaction(masterId, -config.serviceFee, "payment", "Komissiya ödənişi", orderId);
    }

    return { success: true, freeCommission };
});

// 5. Отмены
exports.masterCancelOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const { orderId, reason } = request.data;
    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw new HttpsError('not-found', 'Order not found');
    const od = orderSnap.data();
    if (od?.masterId !== request.auth.uid) throw new HttpsError('permission-denied', 'Not assigned master');

    await orderRef.update({
        formerMasterIds: admin.firestore.FieldValue.arrayUnion(request.auth.uid),
        status: CANCELED_BY_MASTER_STATUS,
        masterId: null,
        cancellationReason: reason || 'unknown'
    });
    return { success: true };
});

exports.clientCancelOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const { orderId, reason } = request.data;
    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) throw new HttpsError('not-found', 'Order not found');
    const od = orderSnap.data();
    if (od?.customerId !== request.auth.uid) throw new HttpsError('permission-denied', 'Not order owner');

    await orderRef.update({
        status: CANCELLED_STATUS,
        cancelledBy: 'client',
        cancellationReason: reason || 'unknown'
    });
    return { success: true };
});

// 🛠️ 6. ✅ ТЕСТОВОЕ ПОПОЛНЕНИЕ (СИМУЛЯТОР ТЕРМИНАЛА)
exports.simulateTopUp = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const uid = request.auth.uid;
    const { userId, amount } = request.data;
    if (!userId || amount == null) throw new HttpsError('invalid-argument', 'No data');
    if (typeof amount !== 'number' || amount <= 0 || amount > 500) {
        throw new HttpsError('invalid-argument', 'Invalid amount');
    }
    if (userId !== uid) throw new HttpsError('permission-denied', 'You can only top up your own account');

    const userRef = db.collection(USERS_COLLECTION).doc(userId);
    await userRef.update({
        balance: admin.firestore.FieldValue.increment(amount)
    });

    // 📜 Лог пополнения
    await _logTransaction(userId, amount, 'topup', 'Terminal (Test)');

    return { success: true, newBalance: 'updated' };
});

exports.submitMasterVerification = onCall(async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
    const uid = request.auth.uid;
    const selfieUrl = String(request.data?.selfieUrl ?? "").trim();
    const docUrl = String(request.data?.docUrl ?? "").trim();
    if (selfieUrl.length < 12 || docUrl.length < 12) {
        throw new HttpsError("invalid-argument", "selfieUrl and docUrl required");
    }
    if (!selfieUrl.startsWith("https://") || !docUrl.startsWith("https://")) {
        throw new HttpsError("invalid-argument", "URLs must be https");
    }
    const uref = db.collection(USERS_COLLECTION).doc(uid);
    const usnap = await uref.get();
    if (!usnap.exists || usnap.get("role") !== MASTER_ROLE) {
        throw new HttpsError("permission-denied", "Master profile only");
    }
    await uref.update({
        verificationStatus: "pending",
        verificationDocs: {
            selfieUrl,
            docUrl,
            submittedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
    });
    void notifyAdminWebhook("master_verification_pending", { masterId: uid });
    return { success: true };
});

exports.incrementMasterEngagement = onCall(async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Auth required");
    const uid = request.auth.uid;
    const counter = String(request.data?.counter ?? "");
    if (counter !== "views" && counter !== "calls") {
        throw new HttpsError("invalid-argument", "counter must be views or calls");
    }
    const field = counter === "views" ? "viewsCount" : "callsCount";
    await db.collection(USERS_COLLECTION).doc(uid).update({
        [field]: admin.firestore.FieldValue.increment(1),
    });
    return { success: true };
});

exports.adminSetMasterVerification = onCall(async (request) => {
    await assertCallerIsAdmin(request);
    const masterId = String(request.data?.masterId ?? "").trim();
    const verificationStatus = String(request.data?.verificationStatus ?? "").trim();
    if (!masterId || (verificationStatus !== "verified" && verificationStatus !== "rejected")) {
        throw new HttpsError("invalid-argument", "masterId and verificationStatus (verified|rejected) required");
    }
    const mref = db.collection(USERS_COLLECTION).doc(masterId);
    const msnap = await mref.get();
    if (!msnap.exists || msnap.get("role") !== MASTER_ROLE) {
        throw new HttpsError("not-found", "Master not found");
    }
    await mref.update({ verificationStatus });
    return { success: true };
});


// =============================================================================
// 4. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ И ХЕЛПЕРЫ
// =============================================================================

/** Волны радара (км): сначала 3, при пустоте — 5, затем 10 (не шире `outerRadiusKm`). */
const RADAR_RING_KM = [3, 5, 10];

function getBakuDateKey(d = new Date()): string {
    return new Intl.DateTimeFormat("en-CA", {
        timeZone: "Asia/Baku",
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
    }).format(d);
}

type EligibleMaster = { masterId: string; token: string; distanceKm: number };

/** Собрать онлайн мастеров по геохэшу и отфильтровать по расстоянию ≤ maxKm. */
async function collectEligibleMastersInRadius(
    lat: number,
    lng: number,
    maxKm: number,
    category: string,
    targetMasterId: string | null,
    excluded: Set<string>,
    clientLatLng: LatLng
): Promise<EligibleMaster[]> {
    const RADIUS_M = maxKm * 1000;
    const center: [number, number] = [lat, lng];
    const bounds = geohashQueryBounds(center, RADIUS_M);
    const promises: Promise<admin.firestore.QuerySnapshot>[] = [];
    for (const b of bounds) {
        promises.push(
            db.collection(USERS_COLLECTION)
                .orderBy("geoHash")
                .startAt(b[0])
                .endBefore(b[1])
                .get()
        );
    }
    const snapshots = await Promise.all(promises);
    const eligible: EligibleMaster[] = [];
    const processedMasterIds = new Set<string>();

    for (const snap of snapshots) {
        for (const doc of snap.docs) {
            const masterId = doc.id;
            if (processedMasterIds.has(masterId)) continue;
            processedMasterIds.add(masterId);
            if (targetMasterId && masterId !== targetMasterId) continue;
            if (excluded.has(masterId)) continue;

            const master = doc.data();
            if (master.role !== MASTER_ROLE) continue;
            if (master.isOnline !== true) continue;
            if (master.status !== "free") continue;

            const masterCategories = master.categories || [];
            if (!Array.isArray(masterCategories) || !masterCategories.includes(category)) continue;

            if (master.fcmToken && master.lastLocation) {
                const masterLatLng = {
                    latitude: master.lastLocation.latitude,
                    longitude: master.lastLocation.longitude,
                };
                const distanceKm = getDistance(clientLatLng, masterLatLng) / 1000;
                if (distanceKm <= maxKm) {
                    eligible.push({ masterId, token: master.fcmToken, distanceKm });
                }
            }
        }
    }
    return eligible;
}

/** UID мастеров, которым уже не шлём радар (imtina / timeout). */
function buildExcludedMasterIds(order: admin.firestore.DocumentData | undefined): Set<string> {
    const declined = Array.isArray(order?.declinedMasterIds) ? (order!.declinedMasterIds as unknown[]) : [];
    const timedOut = Array.isArray(order?.timedOutMasterIds) ? (order!.timedOutMasterIds as unknown[]) : [];
    const ids = [...declined, ...timedOut].filter((id): id is string => typeof id === "string" && id.length > 0);
    return new Set(ids);
}

/** Одно чтение перед отменой: только pending → cancelled (гонка с accept). */
async function _cancelPendingOrderNoMasters(orderRef: admin.firestore.DocumentReference): Promise<boolean> {
    const latest = await orderRef.get();
    if (!latest.exists || latest.get("status") !== PENDING_STATUS) return false;
    await orderRef.update({
        status: CANCELLED_STATUS,
        cancellationReason: "no_masters_found",
        cancelledBy: "system",
    });
    return true;
}

/** Каскадный радар: перечитать заказ и снова разослать FCM (после imtina/timeout). */
async function _runRadarRescan(orderId: string): Promise<void> {
    const config = await getGlobalSettings();
    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) return;
    const o = snap.data()!;
    if (o.status !== PENDING_STATUS) return;

    const loc = o.clientLocation as admin.firestore.GeoPoint | undefined;
    if (!loc || typeof loc.latitude !== "number" || typeof loc.longitude !== "number") {
        console.error(`_runRadarRescan: no clientLocation order=${orderId}`);
        return;
    }

    const targetMasterId = typeof o.targetMasterId === "string" && o.targetMasterId.length > 0
        ? o.targetMasterId
        : null;
    const category = String(o.category ?? "");
    const orderData = { category };

    const isScheduled = o.type === "scheduled";
    if (isScheduled) {
        await _processScheduledOrder(orderId, orderData, loc.latitude, loc.longitude, targetMasterId, config);
    } else {
        await _processEmergencyOrder(orderId, orderData, loc.latitude, loc.longitude, targetMasterId, config);
    }
}

/** Не блокирует ответ callable: ошибки только в лог. */
function scheduleRadarRescan(orderId: string): void {
    void _runRadarRescan(orderId).catch((e) => console.error("scheduleRadarRescan failed", orderId, e));
}

async function _processEmergencyOrder(orderId: string, orderData: any, lat: number, lng: number, targetMasterId: string | null, config: any) {
    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
        return { success: false, orderId, error: "order_missing" };
    }
    if (orderSnap.get("status") !== PENDING_STATUS) {
        return { success: true, orderId, skipped: true };
    }
    const orderPayload = orderSnap.data()!;
    const excluded = buildExcludedMasterIds(orderPayload);
    const category = String(orderPayload.category ?? orderData.category ?? "");

    const outerRadiusKm = Math.min(10, Number(config.radiusKm) || 10);
    const waves = RADAR_RING_KM.filter((w) => w <= outerRadiusKm);
    const queryKm = waves.length > 0 ? Math.max(...waves) : outerRadiusKm;
    const clientLatLng: LatLng = { latitude: lat, longitude: lng };

    console.log(`🗺️ Emergency radar category='${category}' [${lat},${lng}] outer=${queryKm}km excluded=${excluded.size}`);

    const eligible = await collectEligibleMastersInRadius(
        lat,
        lng,
        queryKm,
        category,
        targetMasterId,
        excluded,
        clientLatLng
    );

    let mastersToNotify: EligibleMaster[] = [];
    let radiusWaveKm: number | null = null;
    for (const w of waves.length > 0 ? waves : [queryKm]) {
        const inWave = eligible.filter((m) => m.distanceKm <= w);
        if (inWave.length > 0) {
            mastersToNotify = inWave;
            radiusWaveKm = w;
            break;
        }
    }

    const searchMeta = {
        mastersFound: eligible.length,
        notifiedCount: mastersToNotify.length,
        radiusWaveKm,
        mode: "emergency" as const,
    };

    if (mastersToNotify.length === 0) {
        await orderRef.update({
            searchMeta: {
                ...searchMeta,
                lastSearchAt: admin.firestore.FieldValue.serverTimestamp(),
            },
        });
        const cancelled = await _cancelPendingOrderNoMasters(orderRef);
        return {
            success: true,
            orderId,
            mastersFound: 0,
            cancelledNoMasters: cancelled,
        };
    }

    await orderRef.update({
        searchMeta: {
            ...searchMeta,
            lastSearchAt: admin.firestore.FieldValue.serverTimestamp(),
        },
    });

    await _sendPushNotifications(
        mastersToNotify.map((m) => m.token),
        {
            title: targetMasterId ? "Şəxsi Sifariş!" : "🔥 Yeni Təcili Sifariş!",
            body: `${category} ustası tələb olunur.`,
            orderId: orderId,
            type: "emergency",
            category: category,
            lat: lat,
            lng: lng,
        }
    );

    await appendOrderEvent(orderId, {
        type: "masters_notified",
        actorId: null,
        details: {
            notifiedCount: mastersToNotify.length,
            mode: "emergency",
            radiusWaveKm,
            mastersFound: eligible.length,
        },
    });

    return { success: true, orderId, mastersFound: mastersToNotify.length, radiusWaveKm };
}

async function _processScheduledOrder(orderId: string, orderData: any, lat: number, lng: number, targetMasterId: string | null, config: any) {
    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const orderSnap = await orderRef.get();
    if (!orderSnap.exists) {
        return { success: false, orderId, error: "order_missing" };
    }
    if (orderSnap.get("status") !== PENDING_STATUS) {
        return { success: true, orderId, skipped: true };
    }
    const orderPayload = orderSnap.data()!;
    const excluded = buildExcludedMasterIds(orderPayload);
    const category = String(orderPayload.category ?? orderData.category ?? "");

    if (targetMasterId) {
        if (excluded.has(targetMasterId)) {
            await orderRef.update({
                searchMeta: {
                    mastersFound: 0,
                    notifiedCount: 0,
                    radiusWaveKm: null,
                    mode: "scheduled_direct",
                    lastSearchAt: admin.firestore.FieldValue.serverTimestamp(),
                },
            });
            const cancelled = await _cancelPendingOrderNoMasters(orderRef);
            return { success: true, orderId, mode: "direct", mastersFound: 0, cancelledNoMasters: cancelled };
        }
        const masterDoc = await db.collection(USERS_COLLECTION).doc(targetMasterId).get();
        let notified = 0;
        if (masterDoc.exists) {
            const master = masterDoc.data();
            if (master && master.fcmToken) {
                notified = 1;
                await orderRef.update({
                    searchMeta: {
                        mastersFound: 1,
                        notifiedCount: 1,
                        radiusWaveKm: null,
                        mode: "scheduled_direct",
                        lastSearchAt: admin.firestore.FieldValue.serverTimestamp(),
                    },
                });
                await _sendPushNotifications([master.fcmToken], {
                    title: "📅 Planlı Sifariş",
                    body: `Müştəri sizinlə vaxt təyin etmək istəyir.`,
                    orderId: orderId,
                    type: "scheduled",
                    category: category,
                    lat: lat,
                    lng: lng,
                });
                await appendOrderEvent(orderId, {
                    type: "masters_notified",
                    actorId: null,
                    details: { notifiedCount: 1, mode: "scheduled_direct" },
                });
            }
        }
        if (notified === 0) {
            await orderRef.update({
                searchMeta: {
                    mastersFound: 0,
                    notifiedCount: 0,
                    radiusWaveKm: null,
                    mode: "scheduled_direct",
                    lastSearchAt: admin.firestore.FieldValue.serverTimestamp(),
                },
            });
        }
        return { success: true, orderId, mode: "direct", mastersFound: notified };
    }

    const outerRadiusKm = Math.min(10, Number(config.radiusKm) || 10);
    const waves = RADAR_RING_KM.filter((w) => w <= outerRadiusKm);
    const queryKm = waves.length > 0 ? Math.max(...waves) : outerRadiusKm;
    const clientLatLng: LatLng = { latitude: lat, longitude: lng };

    const eligible = await collectEligibleMastersInRadius(
        lat,
        lng,
        queryKm,
        category,
        null,
        excluded,
        clientLatLng
    );

    let mastersToNotify: EligibleMaster[] = [];
    let radiusWaveKm: number | null = null;
    for (const w of waves.length > 0 ? waves : [queryKm]) {
        const inWave = eligible.filter((m) => m.distanceKm <= w);
        if (inWave.length > 0) {
            mastersToNotify = inWave;
            radiusWaveKm = w;
            break;
        }
    }

    const searchMeta = {
        mastersFound: eligible.length,
        notifiedCount: mastersToNotify.length,
        radiusWaveKm,
        mode: "scheduled_general" as const,
    };

    if (mastersToNotify.length === 0) {
        await orderRef.update({
            searchMeta: {
                ...searchMeta,
                lastSearchAt: admin.firestore.FieldValue.serverTimestamp(),
            },
        });
        const cancelled = await _cancelPendingOrderNoMasters(orderRef);
        return {
            success: true,
            orderId,
            mode: "general",
            mastersFound: 0,
            cancelledNoMasters: cancelled,
        };
    }

    await orderRef.update({
        searchMeta: {
            ...searchMeta,
            lastSearchAt: admin.firestore.FieldValue.serverTimestamp(),
        },
    });

    await _sendPushNotifications(mastersToNotify.map((m) => m.token), {
        title: "📌 Yeni Planlı Sifariş",
        body: `${category} üzrə yeni iş var.`,
        orderId: orderId,
        type: "scheduled",
        category: category,
        lat: lat,
        lng: lng,
    });

    await appendOrderEvent(orderId, {
        type: "masters_notified",
        actorId: null,
        details: {
            notifiedCount: mastersToNotify.length,
            mode: "scheduled_general",
            radiusWaveKm,
            mastersFound: eligible.length,
        },
    });

    return { success: true, orderId, mode: "general", mastersFound: mastersToNotify.length, radiusWaveKm };
}

async function _sendPushNotifications(tokens: string[], data: any) {
    if (!tokens.length) return;
    const uniqueTokens = [...new Set(tokens)];

    const payloadData: any = {
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
        orderId: data.orderId,
        type: data.type,
    };
    if (data.category) payloadData.category = data.category;
    if (data.lat) payloadData.lat = String(data.lat);
    if (data.lng) payloadData.lng = String(data.lng);

    const message = {
        tokens: uniqueTokens,
        data: payloadData,
        notification: { title: data.title, body: data.body },
        android: { priority: 'high' as const, notification: { channelId: 'emergency_orders', sound: 'default' } },
        apns: { payload: { aps: { contentAvailable: true, sound: 'default' } } }
    };

    try {
        await admin.messaging().sendEachForMulticast(message);
    } catch (e) {
        console.error("Push Error:", e);
    }
}

// Мастер imtina / taymer — sonrakı FCM filtrasiyası üçün sifarişdə ID saxlanılır
exports.rejectOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const orderId = request.data?.orderId;
    if (!orderId) throw new HttpsError('invalid-argument', 'orderId required');
    const masterId = request.auth.uid;
    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) throw new HttpsError('not-found', 'Order not found');
    const d = snap.data()!;
    if (d.status !== PENDING_STATUS) throw new HttpsError('failed-precondition', 'Order not pending');
    await orderRef.update({
        declinedMasterIds: admin.firestore.FieldValue.arrayUnion(masterId)
    });
    await appendOrderEvent(orderId, {
        type: "master_declined",
        actorId: masterId,
        details: { source: "rejectOrder" },
    });
    scheduleRadarRescan(orderId);
    return { success: true };
});

exports.registerMasterTimeout = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const orderId = request.data?.orderId;
    const masterIdArg = request.data?.masterId;
    if (!orderId) throw new HttpsError('invalid-argument', 'orderId required');
    if (masterIdArg != null && masterIdArg !== request.auth.uid) {
        throw new HttpsError('permission-denied', 'Invalid master');
    }
    const masterId = request.auth.uid;
    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const snap = await orderRef.get();
    if (!snap.exists) throw new HttpsError('not-found', 'Order not found');
    const d = snap.data()!;
    if (d.status !== PENDING_STATUS) throw new HttpsError('failed-precondition', 'Order not pending');
    await orderRef.update({
        timedOutMasterIds: admin.firestore.FieldValue.arrayUnion(masterId)
    });
    await appendOrderEvent(orderId, {
        type: "master_offer_timeout",
        actorId: masterId,
        details: { source: "registerMasterTimeout" },
    });
    scheduleRadarRescan(orderId);
    return { success: true };
});

exports.generateTestData = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const userDoc = await db.collection(USERS_COLLECTION).doc(request.auth.uid).get();
    if (!userDoc.exists || userDoc.data()?.role !== 'admin') {
        throw new HttpsError('permission-denied', 'Admin only');
    }
    // Real test ustaları üçün Firebase Auth + seed skripti lazımdır
    return { success: true, count: 0 };
});
exports.setAdminClaimTemp = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Auth required');
    await admin.auth().setCustomUserClaims(uid, { role: 'admin' });
    await db.collection(USERS_COLLECTION).doc(uid).update({ role: 'admin' });
    return { success: true };
});