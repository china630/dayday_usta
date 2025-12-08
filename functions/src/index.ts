import * as admin from "firebase-admin";
// -----------------------------------------------------------------------------
// КОММЕНТАРИЙ: Импорты для триггеров (Раскомментировать, когда понадобятся функции ниже)
// import {onDocumentCreated, onDocumentUpdated, Change, FirestoreEvent, QueryDocumentSnapshot} from "firebase-functions/v2/firestore";
// import {geohashForLocation} from "geofire-common";
// -----------------------------------------------------------------------------
import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {getDistance} from "geolib";
import {geohashQueryBounds} from "geofire-common";

// --- Константы ---
setGlobalOptions({region: "europe-west3", maxInstances: 10});
admin.initializeApp();
const db = admin.firestore();

const USERS_COLLECTION = "users";
const ORDERS_COLLECTION = "orders";
const RADIUS_KM = 10;
const RADIUS_M = RADIUS_KM * 1000;

const PENDING_STATUS = "pending";
const ACCEPTED_STATUS = "accepted";
const MASTER_ROLE = "master";

// Константы для триггеров (пока не используются)
// const ARRIVED_STATUS = "arrived";
// const CANCELED_BY_MASTER_STATUS = "canceledByMaster";
const UNAVAILABLE_STATUS = "unavailable";


// -----------------------------------------------------------------------------
// 1. ЕДИНАЯ ТОЧКА ВХОДА: СОЗДАНИЕ ЗАКАЗА (createOrder)
// -----------------------------------------------------------------------------
exports.createOrder = onCall(async (request) => {
    console.log("🚀 START: createOrder called", request.data);

    const {
        clientUserId, category, latitude, longitude,
        type = 'emergency',
        source = 'boltSearch',
        scheduledTime = null,
        targetMasterId = null
    } = request.data;

    if (!clientUserId || !category || !latitude || !longitude) {
        throw new HttpsError('invalid-argument', 'Missing required fields.');
    }

    const orderRef = db.collection(ORDERS_COLLECTION).doc();
    const orderId = orderRef.id;

    const orderData = {
        customerId: clientUserId,
        category: category,
        clientLocation: new admin.firestore.GeoPoint(latitude, longitude),
        status: PENDING_STATUS,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        type: type,
        source: source,
        scheduledTime: scheduledTime ? admin.firestore.Timestamp.fromDate(new Date(scheduledTime)) : null,
        masterId: null,
        targetMasterId: targetMasterId
    };

    await orderRef.set(orderData);
    console.log(`📝 Order created: ${orderId} [${type}] Target: ${targetMasterId}`);

    if (type === 'emergency') {
        return _processEmergencyOrder(orderId, orderData, latitude, longitude, targetMasterId);
    } else {
        return _processScheduledOrder(orderId, orderData, targetMasterId);
    }
});

// -----------------------------------------------------------------------------
// ЛОГИКА А: СРОЧНЫЙ ЗАКАЗ
// -----------------------------------------------------------------------------

async function _processEmergencyOrder(orderId: string, orderData: any, lat: number, lng: number, targetMasterId: string | null) {
    const center: [number, number] = [lat, lng];
    const bounds = geohashQueryBounds(center, RADIUS_M);
    const promises: Promise<admin.firestore.QuerySnapshot>[] = [];

    // Ищем мастеров вокруг
    for (const b of bounds) {
        let query = db.collection(USERS_COLLECTION)
            .orderBy('geoHash')
            .startAt(b[0])
            .endBefore(b[1]);
        promises.push(query.get());
    }

    const snapshots = await Promise.all(promises);
    const mastersToNotify: { token: string, distance: number }[] = [];
    const processedIds = new Set<string>();

    const clientLatLng = { latitude: lat, longitude: lng };

    for (const snap of snapshots) {
        for (const doc of snap.docs) {
            const masterId = doc.id;

            // ✅ ГЛАВНОЕ ИСПРАВЛЕНИЕ: Если это адресный вызов, игнорируем всех остальных
            if (targetMasterId && masterId !== targetMasterId) continue;

            if (processedIds.has(masterId)) continue;
            processedIds.add(masterId);

            const master = doc.data();

            // Проверки
            if (master.role !== MASTER_ROLE) continue;

            // Для срочного заказа мастер должен быть свободен, даже если выбран вручную
            if (master.status !== 'free') continue;

            // Категория
            const cats = master.categories || [];
            if (!cats.includes(orderData.category)) continue;

            // Online (теперь работает!)
            if (master.isOnline !== true) continue;

            // Дистанция
            const mLoc = master.lastLocation;
            if (mLoc) {
                const dist = getDistance(clientLatLng, { latitude: mLoc.latitude, longitude: mLoc.longitude }) / 1000;

                // Если мастер найден (по ID или по радиусу) — добавляем
                if (dist <= RADIUS_KM && master.fcmToken) {
                    mastersToNotify.push({ token: master.fcmToken, distance: dist });
                }
            }
        }
    }

    // Отправка уведомления
    await _sendPushNotifications(mastersToNotify.map(m => m.token), {
        title: targetMasterId ? 'Şəxsi Sifariş!' : '🔥 Yeni Təcili Sifariş!',
        body: `${orderData.category} ustası tələb olunur.`,
        orderId: orderId,
        type: 'emergency',
        category: orderData.category,
        lat: String(lat),
        lng: String(lng)
    });

    return { success: true, orderId, count: mastersToNotify.length, mode: 'emergency' };
}

// -----------------------------------------------------------------------------
// ЛОГИКА Б: ЗАПЛАНИРОВАННЫЙ ЗАКАЗ
// -----------------------------------------------------------------------------
async function _processScheduledOrder(orderId: string, orderData: any, targetMasterId: string | null) {
    const scheduledTime = orderData.scheduledTime ? new Date(orderData.scheduledTime.toDate()).toLocaleString() : 'Vaxt təyin edilməyib';

    // ВАРИАНТ 1: ЗАКАЗ КОНКРЕТНОМУ МАСТЕРУ (ИЗ СПРАВОЧНИКА)
    if (targetMasterId) {
        const masterDoc = await db.collection(USERS_COLLECTION).doc(targetMasterId).get();
        if (!masterDoc.exists) throw new HttpsError('not-found', 'Target master not found');
        const master = masterDoc.data();

        if (master && master.fcmToken) {
            await _sendPushNotifications([master.fcmToken], {
                title: '📅 Planlı Sifariş Təklifi',
                body: `Müştəri sizinlə ${scheduledTime} tarixinə sifariş etmək istəyir.`,
                orderId: orderId,
                type: 'scheduled',
                category: orderData.category
            });
            return { success: true, orderId, count: 1, mode: 'scheduled_direct' };
        }
        return { success: true, count: 0, message: "Master has no token" };
    }

    // ВАРИАНТ 2: ОБЩИЙ ЗАКАЗ (С ГЛАВНОГО ЭКРАНА) -> ИЩЕМ ВСЕХ ВОКРУГ
    else {
        console.log(`🔍 Searching masters for General Scheduled Order: ${orderId}`);

        const lat = orderData.clientLocation.latitude;
        const lng = orderData.clientLocation.longitude;
        const center: [number, number] = [lat, lng];
        const bounds = geohashQueryBounds(center, RADIUS_M);
        const promises: Promise<admin.firestore.QuerySnapshot>[] = [];

        for (const b of bounds) {
            let query = db.collection(USERS_COLLECTION)
                .orderBy('geoHash')
                .startAt(b[0])
                .endBefore(b[1]);
            promises.push(query.get());
        }

        const snapshots = await Promise.all(promises);
        const mastersToNotify: string[] = [];
        const processedIds = new Set<string>();
        const clientLatLng = { latitude: lat, longitude: lng };

        for (const snap of snapshots) {
            for (const doc of snap.docs) {
                const masterId = doc.id;
                if (processedIds.has(masterId)) continue;
                processedIds.add(masterId);

                const master = doc.data();

                // 1. Фильтр Роли
                if (master.role !== MASTER_ROLE) continue;

                // 2. Фильтр Категории
                const cats = master.categories || [];
                if (!cats.includes(orderData.category)) continue;

                // 3. Статус для плановых:
                // Для общих плановых заказов мастер может быть даже 'busy' сейчас,
                // главное, чтобы он был не заблокирован ('unavailable').
                if (master.status === UNAVAILABLE_STATUS) continue;

                // 4. Дистанция
                const mLoc = master.lastLocation;
                if (mLoc) {
                    const dist = getDistance(clientLatLng, { latitude: mLoc.latitude, longitude: mLoc.longitude }) / 1000;
                    if (dist <= RADIUS_KM && master.fcmToken) {
                        mastersToNotify.push(master.fcmToken);
                    }
                }
            }
        }

        // Отправляем всем найденным
        await _sendPushNotifications(mastersToNotify, {
            title: '📅 Yeni Sifariş (Efir)',
            body: `${orderData.category} üçün ${scheduledTime} tarixinə sifariş var. Qəbul etmək üçün tələsin!`,
            orderId: orderId,
            type: 'scheduled', // Важно: тип остается scheduled
            category: orderData.category
        });

        return { success: true, orderId, count: mastersToNotify.length, mode: 'scheduled_general' };
    }
}

// -----------------------------------------------------------------------------
// ВСПОМОГАТЕЛЬНАЯ: ОТПРАВКА PUSH
// -----------------------------------------------------------------------------
async function _sendPushNotifications(tokens: string[], data: any) {
    if (tokens.length === 0) return;
    const validTokens = tokens.filter(t => t && t.length > 10 && t !== "test_token_123");
    if (validTokens.length === 0) return;

    const message = {
        tokens: validTokens,
        data: {
            click_action: 'FLUTTER_NOTIFICATION_CLICK',
            orderId: data.orderId,
            type: data.type,
            category: data.category,
            ...(data.lat && { lat: data.lat }),
            ...(data.lng && { lng: data.lng })
        },
        notification: { title: data.title, body: data.body },
        android: { priority: 'high' as const, notification: { channelId: 'emergency_orders', sound: 'default' } },
        apns: { payload: { aps: { sound: 'default', contentAvailable: true } } }
    };
    try { await admin.messaging().sendEachForMulticast(message); } catch (e) { console.error(e); }
}

/*
// =============================================================================
// ВРЕМЕННО ОТКЛЮЧЕННЫЕ ТРИГГЕРЫ (Чтобы избежать ошибок компиляции)
// Раскомментируйте код и импорты выше, когда будете готовы их использовать.
// =============================================================================

// -----------------------------------------------------------------------------
// 2. ТРИГГЕР: ОБНОВЛЕНИЕ РЕЙТИНГА (onNewReview)
// -----------------------------------------------------------------------------
exports.onNewReview = onDocumentCreated("reviews/{reviewId}", async (event) => {
    const snap = event.data;
    if (!snap) return null;

    const review = snap.data();
    const masterId = review.masterId as string;
    const newRating = review.rating as number;

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

// -----------------------------------------------------------------------------
// 3. ТРИГГЕР: ОБНОВЛЕНИЕ ГЕОХЭША (onMasterLocationUpdate)
// -----------------------------------------------------------------------------
exports.onMasterLocationUpdate = onDocumentUpdated(
    "users/{userId}",
    async (event: FirestoreEvent<Change<QueryDocumentSnapshot> | undefined, { userId: string }>) => {
        if (!event.data) return null;
        const afterData = event.data.after.data();
        if (!afterData || !afterData.lastLocation) return null;
        if (afterData.role !== MASTER_ROLE) return null;

        const beforeLoc = event.data.before.data()?.lastLocation;
        const afterLoc = afterData.lastLocation;

        if (beforeLoc && beforeLoc.latitude === afterLoc.latitude && beforeLoc.longitude === afterLoc.longitude) {
            return null;
        }

        const geoHash = geohashForLocation([afterLoc.latitude, afterLoc.longitude], 9);
        await db.collection(USERS_COLLECTION).doc(event.params.userId).update({ geoHash });
        return null;
    }
);

// -----------------------------------------------------------------------------
// 4. ТРИГГЕР: СМЕНА СТАТУСА ЗАКАЗА (onOrderStatusChange)
// -----------------------------------------------------------------------------
exports.onOrderStatusChange = onDocumentUpdated("orders/{orderId}", async (event) => {
    const change = event.data;
    if (!change) return null;

    const beforeStatus = change.before.data().status;
    const afterStatus = change.after.data().status;
    const masterId = change.after.data().masterId as string;

    if (!masterId || beforeStatus === afterStatus) return null;

    const masterRef = db.collection(USERS_COLLECTION).doc(masterId);
    let shouldUpdateMaster = false;
    let newRejectionsCount: number | null = null;

    if (afterStatus === CANCELED_BY_MASTER_STATUS && beforeStatus === ACCEPTED_STATUS) {
        await db.runTransaction(async (transaction) => {
            const masterDoc = await transaction.get(masterRef);
            if (!masterDoc.exists) return;
            const currentRejections = masterDoc.get('consecutiveRejections') || 0;
            newRejectionsCount = currentRejections + 1;
            shouldUpdateMaster = true;
        });
    }
    else if (afterStatus === ARRIVED_STATUS) {
        newRejectionsCount = 0;
        shouldUpdateMaster = true;
    }

    if (shouldUpdateMaster && newRejectionsCount !== null) {
        const updateData: { consecutiveRejections: number, status?: string } = {
            consecutiveRejections: newRejectionsCount,
        };
        if (newRejectionsCount >= 3) {
            updateData.status = UNAVAILABLE_STATUS;
        }
        await masterRef.update(updateData);
    }
    return null;
});
*/

// -----------------------------------------------------------------------------
// 5. ПРИНЯТИЕ ЗАКАЗА (acceptOrder)
// -----------------------------------------------------------------------------
exports.acceptOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const masterId = request.auth.uid;
    const { orderId } = request.data;
    if (!orderId) throw new HttpsError('invalid-argument', 'Order ID required');

    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const masterRef = db.collection(USERS_COLLECTION).doc(masterId);

    await db.runTransaction(async (t) => {
        const oDoc = await t.get(orderRef);
        const mDoc = await t.get(masterRef);

        if (!oDoc.exists) throw new HttpsError('not-found', 'Order not found');
        if (!mDoc.exists) throw new HttpsError('not-found', 'Master not found');

        const orderData = oDoc.data();
        if (orderData?.status !== PENDING_STATUS) throw new HttpsError('failed-precondition', 'Order unavailable');

        if (orderData?.type === 'scheduled' && orderData?.targetMasterId && orderData.targetMasterId !== masterId) {
             throw new HttpsError('permission-denied', 'Order for another master');
        }

        t.update(orderRef, { status: ACCEPTED_STATUS, masterId: masterId, acceptedAt: admin.firestore.FieldValue.serverTimestamp() });

        if (orderData?.type === 'emergency') {
             t.update(masterRef, { status: 'busy' });
        }
    });
    return { success: true };
});

// -----------------------------------------------------------------------------
// 6. ОТКЛОНЕНИЕ ЗАКАЗА (rejectOrder)
// -----------------------------------------------------------------------------
exports.rejectOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const { orderId } = request.data;
    console.log(`Master ${request.auth.uid} rejected ${orderId}`);
    return { success: true };
});

// -----------------------------------------------------------------------------
// 7. ТАЙМАУТ (registerMasterTimeout)
// -----------------------------------------------------------------------------
exports.registerMasterTimeout = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const { orderId, masterId } = request.data;
    console.log(`Timeout: Master ${masterId} on Order ${orderId}`);
    return { success: true };
});

// -----------------------------------------------------------------------------
// 8. СЛУЖЕБНЫЕ
// -----------------------------------------------------------------------------
exports.generateTestData = onCall(async (request) => {
    return { success: true, count: 0 };
});

exports.setAdminClaimTemp = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Auth required');
    await admin.auth().setCustomUserClaims(uid, { role: 'admin', admin: true });
    await db.collection(USERS_COLLECTION).doc(uid).update({ role: 'admin' });
    return { message: 'Admin set' };
});

// -----------------------------------------------------------------------------
// ЭКСПОРТ
// -----------------------------------------------------------------------------
exports.createOrder = exports.createOrder;
exports.acceptOrder = exports.acceptOrder;
exports.rejectOrder = exports.rejectOrder;
exports.registerMasterTimeout = exports.registerMasterTimeout;
exports.generateTestData = exports.generateTestData;
exports.setAdminClaimTemp = exports.setAdminClaimTemp;

// Раскомментируйте, когда восстановите функции выше
// exports.onNewReview = exports.onNewReview;
// exports.onMasterLocationUpdate = exports.onMasterLocationUpdate;
// exports.onOrderStatusChange = exports.onOrderStatusChange;