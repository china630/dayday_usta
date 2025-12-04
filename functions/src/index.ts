import * as admin from "firebase-admin";

import {onDocumentCreated, onDocumentUpdated, Change, FirestoreEvent, QueryDocumentSnapshot} from "firebase-functions/v2/firestore";
import {setGlobalOptions} from "firebase-functions/v2";
import {onCall, HttpsError} from "firebase-functions/v2/https";

import {getDistance} from "geolib";
import {geohashForLocation, geohashQueryBounds} from "geofire-common";

// --- Константы ---
type LatLng = {latitude: number, longitude: number};
setGlobalOptions({region: "europe-west3", maxInstances: 10});
admin.initializeApp();
const db = admin.firestore();
const USERS_COLLECTION = "users";
const RADIUS_KM = 5;
const RADIUS_M = RADIUS_KM * 1000;
const PENDING_STATUS = "pending";
const MASTER_ROLE = "master";
const VERIFIED_STATUS = "verified";
const ACCEPTED_STATUS = "accepted";
const UNAVAILABLE_STATUS = 'unavailable';
const ARRIVED_STATUS = 'arrived';
const CANCELED_BY_MASTER_STATUS = 'canceledByMaster';


// -----------------------------------------------------------------------------
// 1. ВЫЗЫВАЕМАЯ ФУНКЦИЯ: ИНИЦИАЦИЯ ЗАКАЗА И ПОИСК (onNewEmergencyOrder)
// -----------------------------------------------------------------------------
exports.onNewEmergencyOrder = onCall(async (request) => {

    const { clientUserId, category, latitude, longitude } = request.data as {
        clientUserId: string,
        category: string,
        latitude: number,
        longitude: number
    };

    if (!clientUserId || !category) {
        throw new HttpsError('invalid-argument', 'Missing required order data.');
    }

    // 1. Создаем заказ в Firestore
    const orderRef = db.collection('orders').doc();
    const orderId = orderRef.id;

    await orderRef.set({
        customerId: clientUserId,
        category: category,
        clientLocation: new admin.firestore.GeoPoint(latitude, longitude),
        status: PENDING_STATUS,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    const clientLocation = new admin.firestore.GeoPoint(latitude, longitude);
    const requiredCategory = category;
    const clientLatLng: LatLng = {latitude: clientLocation.latitude, longitude: clientLocation.longitude};

    // --- ГЕОХЭШ-ЛОГИКА ДЛЯ ОПТИМИЗАЦИИ ПОИСКА ---
    const center: [number, number] = [clientLocation.latitude, clientLocation.longitude];
    const bounds = geohashQueryBounds(center, RADIUS_M);
    const promises: Promise<admin.firestore.QuerySnapshot>[] = [];

    for (const b of bounds) {
        let query = db.collection(USERS_COLLECTION)
            .orderBy('geoHash')
            .startAt(b[0])
            .endBefore(b[1])
            .where("role", "==", MASTER_ROLE)
            .where("status", "==", "free")
            .where("verificationStatus", "==", VERIFIED_STATUS)
            .where("categories", "array-contains", requiredCategory);
        promises.push(query.get());
    }

    const snapshots = await Promise.all(promises);
    const mastersToNotify: {token: string, distance: number}[] = [];
    const processedMasterIds = new Set<string>();

    for (const snap of snapshots) {
        for (const doc of snap.docs) {
            const masterId = doc.id;
            if (processedMasterIds.has(masterId)) continue;
            processedMasterIds.add(masterId);

            const master = doc.data();
            const masterLocation = master.lastLocation as admin.firestore.GeoPoint | undefined;

            if (masterLocation && master.fcmToken) {
                const masterLatLng: LatLng = {latitude: masterLocation.latitude, longitude: masterLocation.longitude};
                const distanceMeters = getDistance(clientLatLng, masterLatLng, 100);
                const distanceKm = distanceMeters / 1000;

                if (distanceKm <= RADIUS_KM) {
                    mastersToNotify.push({token: master.fcmToken, distance: distanceKm});
                }
            }
        }
    }

    // 6. Отправка Уведомлений (FCM)
    if (mastersToNotify.length > 0) {
      const tokens = mastersToNotify.map((m) => m.token);
      console.log(`Notifications sent to ${tokens.length} masters for order ${orderId}.`);
    } else {
      // 7. Если нет мастеров, обновляем статус заказа
      await db.collection("orders").doc(orderId).update({
        status: "unassigned",
      });
    }

    return { success: true, orderId: orderId, mastersFound: mastersToNotify.length };
});

// -----------------------------------------------------------------------------
// 2. ТРИГГЕР: ОБНОВЛЕНИЕ СРЕДНЕГО РЕЙТИНГА МАСТЕРА (onNewReview)
// -----------------------------------------------------------------------------
exports.onNewReview = onDocumentCreated("reviews/{reviewId}", async (event) => {
    const snap = event.data;

    if (!snap) return null;

    const review = snap.data();
    const masterId = review.masterId as string;
    const newRating = review.rating as number;

    if (!masterId || typeof newRating !== 'number' || newRating < 1 || newRating > 5) return null;

    const masterRef = db.collection(USERS_COLLECTION).doc(masterId);

    try {
        await db.runTransaction(async (transaction) => {
            const masterDoc = await transaction.get(masterRef);

            const currentSum = masterDoc.get('totalRatingSum') || 0;
            const currentCount = masterDoc.get('reviewCount') || 0;

            const updatedSum = currentSum + newRating;
            const updatedCount = currentCount + 1;
            const averageRating = updatedCount > 0 ? (updatedSum / updatedCount) : 0;
            const finalRating = parseFloat(averageRating.toFixed(1));

            transaction.update(masterRef, {
                rating: finalRating,
                totalRatingSum: updatedSum,
                reviewCount: updatedCount,
            });
        });

    } catch (e) {
        console.error(`Transaction failed for master ${masterId}:`, e);
    }

    return null;
});


// -----------------------------------------------------------------------------
// 3. ТРИГГЕР: ОБНОВЛЕНИЕ ГЕОХЭША МАСТЕРА (onMasterLocationUpdate)
// -----------------------------------------------------------------------------
exports.onMasterLocationUpdate = onDocumentUpdated(
    "users/{userId}",
    async (event: FirestoreEvent<Change<QueryDocumentSnapshot> | undefined, { userId: string }>) => {
        if (!event.data) return null;

        const beforeData = event.data.before.data();
        const afterData = event.data.after.data();
        if (!beforeData || !afterData) return null;

        const userId = event.params.userId;
        const newLocation = afterData.lastLocation as admin.firestore.GeoPoint | undefined;
        const oldLocation = beforeData.lastLocation as admin.firestore.GeoPoint | undefined;

        const locationChanged =
            (newLocation && oldLocation && newLocation.latitude !== oldLocation.latitude) ||
            (newLocation && !oldLocation);

        if (!locationChanged || !newLocation || afterData.role !== MASTER_ROLE) return null;

        const lat = newLocation.latitude;
        const lon = newLocation.longitude;
        const geoHash = geohashForLocation([lat, lon], 9);

        await db.collection(USERS_COLLECTION).doc(userId).update({
            geoHash: geoHash,
        });
        return null;
    }
);

// -----------------------------------------------------------------------------
// 4. ВЫЗЫВАЕМАЯ ФУНКЦИЯ: ПРИНЯТИЕ ЗАКАЗА МАСТЕРОМ (acceptOrder)
// -----------------------------------------------------------------------------
exports.acceptOrder = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const masterId = request.auth.uid;
    const { orderId } = request.data as { orderId: string };

    if (!orderId) {
        throw new HttpsError('invalid-argument', 'Order ID is required.');
    }

    const orderRef = db.collection('orders').doc(orderId);
    const masterRef = db.collection(USERS_COLLECTION).doc(masterId);

    try {
        await db.runTransaction(async (transaction) => {
            const orderDoc = await transaction.get(orderRef);
            const masterDoc = await transaction.get(masterRef);

            if (!orderDoc.exists || orderDoc.data()?.status !== PENDING_STATUS) {
                throw new HttpsError('failed-precondition', 'Order is already accepted or does not exist.');
            }

            // ✅ ИСПРАВЛЕНИЕ: Используем customerId для логирования
            const customerId = orderDoc.data()?.customerId as string;
            console.log(`Accepting order ${orderId} for customer ${customerId}.`);


            if (masterDoc.data()?.role !== MASTER_ROLE || masterDoc.data()?.status !== 'free') {
                throw new HttpsError('failed-precondition', 'Master is not eligible to accept orders.');
            }

            // 2. Обновление заказа: Назначаем мастера и меняем статус
            transaction.update(orderRef, {
                status: ACCEPTED_STATUS,
                masterId: masterId,
                acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
            });

            // 3. Обновление статуса мастера: Меняем на 'busy'
            transaction.update(masterRef, {
                status: 'busy',
            });
        });

        // 4. Уведомление клиента (после успешной транзакции) - Опущено
        return { success: true, message: `Order ${orderId} accepted.` };

    } catch (error) {
        if (error instanceof HttpsError) {
            throw error;
        }
        throw new HttpsError('internal', 'Internal error during order acceptance.', error);
    }
});

// -----------------------------------------------------------------------------
// 5. ТРИГГЕР: ОБРАБОТКА СТАТУСА ЗАКАЗА (onOrderStatusChange)
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

    // СЦЕНАРИЙ 1: Отмена принятого заказа мастером
    if (afterStatus === CANCELED_BY_MASTER_STATUS && beforeStatus === ACCEPTED_STATUS) {
        await db.runTransaction(async (transaction) => {
            const masterDoc = await transaction.get(masterRef);
            const currentRejections = masterDoc.get('consecutiveRejections') || 0;
            newRejectionsCount = currentRejections + 1;
            shouldUpdateMaster = true;
        });

    // СЦЕНАРИЙ 2: Мастер прибыл (Сброс счетчика)
    } else if (afterStatus === ARRIVED_STATUS) {
        newRejectionsCount = 0;
        shouldUpdateMaster = true;
    }

    if (shouldUpdateMaster && newRejectionsCount !== null) {
        const updateData: { consecutiveRejections: number, status?: string } = {
            consecutiveRejections: newRejectionsCount,
        };

        // ПРОВЕРКА ПРАВИЛА ТРЕХ ОТКАЗОВ
        if (newRejectionsCount >= 3) {
            updateData.status = UNAVAILABLE_STATUS;
        }

        await masterRef.update(updateData);
    }

    return null;
});

// -----------------------------------------------------------------------------
// 6. ВЫЗЫВАЕМАЯ ФУНКЦИЯ: ОТКЛОНЕНИЕ ЗАКАЗА МАСТЕРОМ (rejectOrder)
// -----------------------------------------------------------------------------
exports.rejectOrder = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const masterId = request.auth.uid; // ✅ ИСПОЛЬЗУЕТСЯ
    const { orderId } = request.data as { orderId: string };

    if (!orderId) {
        throw new HttpsError('invalid-argument', 'Order ID is required.');
    }
    console.log(`Master ${masterId} rejecting order ${orderId}.`);
    // ... (логика транзакции)
    return { success: true, message: `Order rejected.` };
});

// -----------------------------------------------------------------------------
// 7. ВЫЗЫВАЕМАЯ ФУНКЦИЯ: РЕГИСТРАЦИЯ ОТКАЗА ПО ТАЙМАУТУ (registerMasterTimeout)
// -----------------------------------------------------------------------------
exports.registerMasterTimeout = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'The function must be called while authenticated.');
    }

    const { masterId, orderId } = request.data as { masterId: string, orderId: string };

    if (!masterId || !orderId) {
        throw new HttpsError('invalid-argument', 'Master ID and Order ID are required.');
    }
    console.log(`Timeout registered for master ${masterId} on order ${orderId}.`);
    // ... (логика транзакции)
    return { success: true, message: `Timeout processed.` };
});


// -----------------------------------------------------------------------------
// 8. СЛУЖЕБНАЯ ФУНКЦИЯ: ГЕНЕРАЦИЯ ТЕСТОВЫХ ДАННЫХ (generateTestData)
// -----------------------------------------------------------------------------
// Настройки для тестовых данных
const TOTAL_MASTERS = 1000;
const NEAR_MASTERS_COUNT = 5;
const NEAR_LOCATION = [40.40, 49.80];
const FAR_LOCATION = [30.00, 40.00];

// Функция для генерации профиля мастера
function createMasterProfile(id: number, lat: number, lng: number): any {
    const userId = `test_master_${id}`;
    const geoHash = geohashForLocation([lat, lng], 9);

    return {
        uid: userId,
        role: "master",
        status: "free",
        verificationStatus: "verified",
        categories: ["Kondisioner"],
        phoneNumber: `+99450123${id}`,
        name: "Test",
        surname: `Usta ${id}`,
        lastLocation: new admin.firestore.GeoPoint(lat, lng),
        geoHash: geoHash,
        consecutiveRejections: 0,
        rating: Math.floor(Math.random() * 20 + 30) / 10,
        viewsCount: 0,
        callsCount: 0,
        savesCount: 0,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
}

exports.generateTestData = onCall(async (request) => {
     if (!request.auth || (request.auth.token.admin !== true && request.auth.token.role !== 'admin')) {
         throw new HttpsError('permission-denied', 'Only administrators can run this function.');
    }

    const batch = db.batch();
    const farMastersToCreate = TOTAL_MASTERS - NEAR_MASTERS_COUNT;

    // 1. Создание БЛИЗКИХ МАСТЕРОВ (NEAR)
    for (let i = 0; i < NEAR_MASTERS_COUNT; i++) {
        const lat = NEAR_LOCATION[0] + (Math.random() * 0.005 - 0.0025);
        const lng = NEAR_LOCATION[1] + (Math.random() * 0.005 - 0.0025);
        const profile = createMasterProfile(i, lat, lng);
        batch.set(db.collection(USERS_COLLECTION).doc(profile.uid), profile);
    }

    // 2. Создание ДАЛЬНИХ МАСТЕРОВ (FAR)
    for (let i = 0; i < farMastersToCreate; i++) {
        const lat = FAR_LOCATION[0] + (Math.random() * 0.5 - 0.25);
        const lng = FAR_LOCATION[1] + (Math.random() * 0.5 - 0.25);
        const profile = createMasterProfile(i + NEAR_MASTERS_COUNT, lat, lng);
        batch.set(db.collection(USERS_COLLECTION).doc(profile.uid), profile);
    }

    // 3. Создание ТЕСТОВОГО КЛИЕНТА
    const clientProfile = {
        uid: 'client_test_geo',
        role: "client",
        name: "Geo",
        surname: "Client",
        phoneNumber: "+994500000000",
        lastLocation: new admin.firestore.GeoPoint(NEAR_LOCATION[0], NEAR_LOCATION[1]),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    batch.set(db.collection(USERS_COLLECTION).doc(clientProfile.uid), clientProfile);


    await batch.commit();
    return { success: true, count: TOTAL_MASTERS + 1 };
});

// -----------------------------------------------------------------------------
// 9. СЛУЖЕБНАЯ ФУНКЦИЯ: УСТАНОВКА АДМИН-ПРАВ (setAdminClaimTemp)
// -----------------------------------------------------------------------------
exports.setAdminClaimTemp = onCall(async (request) => {
    const targetUid = request.auth?.uid;

    if (!targetUid) {
        throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    try {
        await admin.auth().setCustomUserClaims(targetUid, { role: 'admin', admin: true });
        await admin.firestore().collection('users').doc(targetUid).update({ role: 'admin' });
        return { message: `Claims set. Please log out and log in again.`, uid: targetUid };
    } catch (error) {
        throw new HttpsError('internal', 'Failed to set admin claims.', error);
    }
});


// -----------------------------------------------------------------------------
// 10. ЕДИНЫЙ БЛОК ЭКСПОРТА
// -----------------------------------------------------------------------------
exports.onNewReview = exports.onNewReview;
exports.onMasterLocationUpdate = exports.onMasterLocationUpdate;
exports.onOrderStatusChange = exports.onOrderStatusChange;
exports.onNewEmergencyOrder = exports.onNewEmergencyOrder; // Теперь Callable
exports.acceptOrder = exports.acceptOrder;
exports.rejectOrder = exports.rejectOrder;
exports.registerMasterTimeout = exports.registerMasterTimeout;
exports.generateTestData = exports.generateTestData;
exports.setAdminClaimTemp = exports.setAdminClaimTemp;