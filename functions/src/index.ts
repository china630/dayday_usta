import * as admin from "firebase-admin";
import {onDocumentCreated, onDocumentUpdated, Change, FirestoreEvent, QueryDocumentSnapshot} from "firebase-functions/v2/firestore";
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getDistance } from "geolib";
import { geohashQueryBounds, geohashForLocation } from "geofire-common";

// --- Константы ---
type LatLng = { latitude: number, longitude: number };

setGlobalOptions({ region: "europe-west3", maxInstances: 10 });

if (admin.apps.length === 0) {
    admin.initializeApp();
}
const db = admin.firestore();

const USERS_COLLECTION = "users";
const ORDERS_COLLECTION = "orders";
const RADIUS_KM = 10;
const RADIUS_M = RADIUS_KM * 1000;

const MASTER_ROLE = "master";
const PENDING_STATUS = "pending";
const ACCEPTED_STATUS = "accepted";
const ARRIVED_STATUS = "arrived";
// ✅ Добавлены недостающие статусы
const COMPLETED_STATUS = "completed";
const CANCELLED_STATUS = "cancelled";
const UNAVAILABLE_STATUS = "unavailable";
const CANCELED_BY_MASTER_STATUS = "canceledByMaster";


// =============================================================================
// 1. ТРИГГЕРЫ (АВТОМАТИКА)
// =============================================================================

// А. Обновление GeoHash при движении мастера
exports.onMasterLocationUpdate = onDocumentUpdated(
    "users/{userId}",
    async (event: FirestoreEvent<Change<QueryDocumentSnapshot> | undefined, { userId: string }>) => {
        if (!event.data) return null;

        const afterData = event.data.after.data();
        const beforeData = event.data.before.data();

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

// Б. Обновление рейтинга при отзыве
exports.onNewReview = onDocumentCreated("reviews/{reviewId}", async (event) => {
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

// В. Контроль статусов (Наказание, Сброс и ОСВОБОЖДЕНИЕ)
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

        if (!masterId || beforeStatus === afterStatus) return null;

        const masterRef = db.collection(USERS_COLLECTION).doc(masterId);
        let shouldUpdateMaster = false;
        let newRejectionsCount: number | null = null;
        let newMasterStatus: string | null = null; // ✅ Переменная для смены статуса

        // 1. Мастер отменил (Наказание)
        if (afterStatus === CANCELED_BY_MASTER_STATUS && beforeStatus === ACCEPTED_STATUS) {
            await db.runTransaction(async (transaction) => {
                const masterDoc = await transaction.get(masterRef);
                if (!masterDoc.exists) return;

                const currentRejections = masterDoc.data()?.consecutiveRejections || 0;
                newRejectionsCount = currentRejections + 1;
                newMasterStatus = 'free'; // ✅ Освобождаем мастера
                shouldUpdateMaster = true;
            });
        }
        // 2. Мастер прибыл (Сброс счетчика)
        else if (afterStatus === ARRIVED_STATUS) {
            newRejectionsCount = 0;
            shouldUpdateMaster = true;
        }
        // 3. ✅ ДОБАВЛЕНО: Заказ завершен или отменен -> Освобождаем мастера
        else if (afterStatus === COMPLETED_STATUS || afterStatus === CANCELLED_STATUS) {
            newMasterStatus = 'free';
            shouldUpdateMaster = true;
        }

        if (shouldUpdateMaster) {
            const updateData: any = {};

            if (newRejectionsCount !== null) {
                updateData.consecutiveRejections = newRejectionsCount;
                if (newRejectionsCount >= 3) {
                    updateData.status = UNAVAILABLE_STATUS;
                    updateData.isOnline = false;
                    console.log(`⛔ Master ${masterId} blocked due to 3 rejections.`);
                }
            }

            // Если нужно сменить статус (и мастер не заблокирован)
            if (newMasterStatus && updateData.status !== UNAVAILABLE_STATUS) {
                updateData.status = newMasterStatus;
            }

            // Только если есть что обновлять
            if (Object.keys(updateData).length > 0) {
                await masterRef.update(updateData);
            }
        }

        return null;
    }
);


// =============================================================================
// 2. ВЫЗЫВАЕМАЯ ФУНКЦИЯ: СОЗДАНИЕ ЗАКАЗА (createOrder)
// =============================================================================
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
        throw new HttpsError('invalid-argument', 'Missing required order data.');
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
        targetMasterId: targetMasterId
    };

    await orderRef.set(orderData);

    if (type === 'emergency') {
        return _processEmergencyOrder(orderId, orderData, latitude, longitude, targetMasterId);
    } else {
        return _processScheduledOrder(orderId, orderData, latitude, longitude, targetMasterId);
    }
});

// ЛОГИКА СРОЧНОГО ПОИСКА
async function _processEmergencyOrder(orderId: string, orderData: any, lat: number, lng: number, targetMasterId: string | null) {
    const center: [number, number] = [lat, lng];
    const bounds = geohashQueryBounds(center, RADIUS_M);
    const promises: Promise<admin.firestore.QuerySnapshot>[] = [];
    const clientLatLng: LatLng = { latitude: lat, longitude: lng };

    console.log(`🗺️ Searching category: '${orderData.category}' around [${lat}, ${lng}]`);

    for (const b of bounds) {
        let query = db.collection(USERS_COLLECTION)
            .orderBy('geoHash')
            .startAt(b[0])
            .endBefore(b[1]);
        promises.push(query.get());
    }

    const snapshots = await Promise.all(promises);
    const mastersToNotify: { token: string, distance: number }[] = [];
    const processedMasterIds = new Set<string>();

    let totalCandidates = 0;

    for (const snap of snapshots) {
        for (const doc of snap.docs) {
            const masterId = doc.id;

            if (processedMasterIds.has(masterId)) continue;
            processedMasterIds.add(masterId);

            if (targetMasterId && masterId !== targetMasterId) continue;

            const master = doc.data();
            totalCandidates++;

            if (master.role !== MASTER_ROLE) continue;
            if (master.isOnline !== true) continue;
            if (master.status !== 'free') continue;

            const masterCategories = master.categories || [];
            if (!Array.isArray(masterCategories) || !masterCategories.includes(orderData.category)) {
                continue;
            }

            if (!master.fcmToken) {
                console.log(`⚠️ Master ${masterId} matches but has NO TOKEN.`);
                continue;
            }

            const masterLocation = master.lastLocation;
            if (masterLocation) {
                const masterLatLng: LatLng = { latitude: masterLocation.latitude, longitude: masterLocation.longitude };
                const distanceMeters = getDistance(clientLatLng, masterLatLng);
                const distanceKm = distanceMeters / 1000;

                if (distanceKm <= RADIUS_KM) {
                    console.log(`✅ MATCH: ${master.name} found! Dist: ${distanceKm.toFixed(2)}km`);
                    mastersToNotify.push({ token: master.fcmToken, distance: distanceKm });
                }
            }
        }
    }

    console.log(`📊 Stats: Candidates: ${totalCandidates}, Matches: ${mastersToNotify.length}`);

    await _sendPushNotifications(mastersToNotify.map(m => m.token), {
        title: targetMasterId ? 'Şəxsi Sifariş!' : '🔥 Yeni Təcili Sifariş!',
        body: `${orderData.category} ustası tələb olunur.`,
        orderId: orderId,
        type: 'emergency',
        category: orderData.category,
        lat: lat,
        lng: lng
    });

    return {
        success: true,
        orderId: orderId,
        mastersFound: mastersToNotify.length
    };
}

// ✅ ЛОГИКА ПЛАНОВОГО ЗАКАЗА (ИСПРАВЛЕНА)
async function _processScheduledOrder(orderId: string, orderData: any, lat: number, lng: number, targetMasterId: string | null) {

    // 1. Если есть конкретный мастер (Catalog Direct)
    if (targetMasterId) {
        const masterDoc = await db.collection(USERS_COLLECTION).doc(targetMasterId).get();
        if (masterDoc.exists) {
            const master = masterDoc.data();
            if (master && master.fcmToken) {
                await _sendPushNotifications([master.fcmToken], {
                    title: '📅 Planlı Sifariş',
                    body: `Müştəri sizinlə vaxt təyin etmək istəyir.`,
                    orderId: orderId,
                    type: 'scheduled',
                    category: orderData.category,
                    lat: lat,
                    lng: lng
                });
            }
        }
        return { success: true, orderId, mode: 'direct' };
    }

    // 2. ✅ ЕСЛИ ЗАКАЗ ОБЩИЙ (Main Screen) - Ищем мастеров вокруг
    else {
        // Используем ту же логику поиска, что и в emergency
        const center: [number, number] = [lat, lng];
        const bounds = geohashQueryBounds(center, RADIUS_M);
        const promises: Promise<admin.firestore.QuerySnapshot>[] = [];

        for (const b of bounds) {
            let query = db.collection(USERS_COLLECTION).orderBy('geoHash').startAt(b[0]).endBefore(b[1]);
            promises.push(query.get());
        }

        const snapshots = await Promise.all(promises);
        const mastersToNotify: { token: string, distance: number }[] = [];
        const processedMasterIds = new Set<string>();

        for (const snap of snapshots) {
            for (const doc of snap.docs) {
                const masterId = doc.id;
                if (processedMasterIds.has(masterId)) continue;
                processedMasterIds.add(masterId);

                const master = doc.data();
                // Фильтры: Мастер, Онлайн, Свободен, Категория
                if (master.role !== MASTER_ROLE) continue;
                if (master.isOnline !== true) continue;
                if (master.status !== 'free') continue;

                const masterCategories = master.categories || [];
                if (!Array.isArray(masterCategories) || !masterCategories.includes(orderData.category)) continue;

                if (master.fcmToken) {
                    mastersToNotify.push({ token: master.fcmToken, distance: 0 }); // Расстояние тут можно не считать детально
                }
            }
        }

        console.log(`📊 Scheduled General: Found ${mastersToNotify.length} masters`);

        await _sendPushNotifications(mastersToNotify.map(m => m.token), {
            title: '📌 Yeni Planlı Sifariş',
            body: `${orderData.category} üzrə yeni iş var.`,
            orderId: orderId,
            type: 'scheduled',
            category: orderData.category,
            lat: lat,
            lng: lng
        });

        return { success: true, orderId, mode: 'general', mastersFound: mastersToNotify.length };
    }
}


// =============================================================================
// 3. ФУНКЦИЯ ПРИНЯТИЯ ЗАКАЗА
// =============================================================================
exports.acceptOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');

    const masterId = request.auth.uid;
    const { orderId } = request.data;

    const orderRef = db.collection(ORDERS_COLLECTION).doc(orderId);
    const masterRef = db.collection(USERS_COLLECTION).doc(masterId);

    await db.runTransaction(async (t) => {
        const oDoc = await t.get(orderRef);
        if (!oDoc.exists) throw new HttpsError('not-found', 'Order not found');

        const orderData = oDoc.data();
        if (orderData?.status !== PENDING_STATUS) throw new HttpsError('failed-precondition', 'Order already taken');

        t.update(orderRef, {
            status: ACCEPTED_STATUS,
            masterId: masterId,
            acceptedAt: admin.firestore.FieldValue.serverTimestamp()
        });

        // Мастер становится занятым
        t.update(masterRef, { status: 'busy' });
    });
    return { success: true, message: `Order ${orderId} accepted.` };
});

// ✅ НОВЫЕ ФУНКЦИИ (которых не было в вашем файле)

// Б. Мастер Прибыл
exports.masterArrived = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    await db.collection(ORDERS_COLLECTION).doc(request.data.orderId).update({
        status: ARRIVED_STATUS,
        arrivedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    return { success: true };
});

// В. Мастер Завершил
exports.masterCompleteOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    const orderId = request.data.orderId;

    // Ставим статус заказа completed
    await db.collection(ORDERS_COLLECTION).doc(orderId).update({
        status: COMPLETED_STATUS,
        completedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    // Статус мастера "free" обновится автоматически через триггер onOrderStatusChange
    return { success: true };
});

// Г. Мастер Отменил
exports.masterCancelOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    await db.collection(ORDERS_COLLECTION).doc(request.data.orderId).update({
        status: CANCELED_BY_MASTER_STATUS,
        masterId: null
    });
    return { success: true };
});

// Д. Клиент Отменил
exports.clientCancelOrder = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Auth required');
    await db.collection(ORDERS_COLLECTION).doc(request.data.orderId).update({
        status: CANCELLED_STATUS,
        cancelledBy: 'client'
    });
    return { success: true };
});


// =============================================================================
// 4. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
// =============================================================================
exports.rejectOrder = onCall(async (request) => { return { success: true }; });
exports.registerMasterTimeout = onCall(async (request) => { return { success: true }; });
exports.generateTestData = onCall(async (request) => { return { success: true, count: 0 }; });
exports.setAdminClaimTemp = onCall(async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError('unauthenticated', 'Auth required');
    await admin.auth().setCustomUserClaims(uid, { role: 'admin' });
    await db.collection(USERS_COLLECTION).doc(uid).update({ role: 'admin' });
    return { success: true };
});

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
        android: {
            priority: 'high' as const,
            notification: {
                channelId: 'emergency_orders',
                sound: 'default'
            }
        },
        apns: { payload: { aps: { contentAvailable: true, sound: 'default' } } }
    };

    try {
        await admin.messaging().sendEachForMulticast(message);
        console.log(`📨 Sent ${uniqueTokens.length} pushes with RICH data`);
    } catch (e) {
        console.error("Push Error:", e);
    }
}

// =============================================================================
// 5. ПРОВЕРКА ЛИМИТА ОТКАЗОВ
// =============================================================================
exports.checkMasterRefusalLimit = onDocumentUpdated(
    "users/{userId}",
    async (event: FirestoreEvent<Change<QueryDocumentSnapshot> | undefined, { userId: string }>) => {

        if (!event.data) return null;

        const newData = event.data.after.data();
        const oldData = event.data.before.data();

        if (!newData || !oldData) return null;
        if (newData.refusal_count === oldData.refusal_count) return null;

        if (newData.refusal_count >= 3 && newData.isOnline === true) {
            const masterId = event.params.userId;
            console.log(`Master ${masterId} kicked offline due to 3 consecutive refusals.`);

            try {
                await event.data.after.ref.update({
                    isOnline: false,
                    status: 'unavailable',
                    refusal_count: 0,
                    last_kicked_offline_at: admin.firestore.FieldValue.serverTimestamp()
                });
            } catch (error) {
                console.error(`Error kicking master ${masterId} offline:`, error);
            }
        }
        return null;
    }
);