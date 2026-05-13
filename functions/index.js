/**
 * RettBase Campus – Cloud Functions (nur dieses Repository / Projekt rettbase-campus).
 * Enthält: kundeExists, ensureUsersDoc (gleiche Callable-Namen wie üblich in der Flutter-App).
 *
 * Kein Bezug zu Quellcode oder Deployments der RettBase-Haupt-App.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// --- Rate-Limit kundeExists (Enumerationsschutz) ---
const _kundeExistsRateLimit = new Map();
const KUNDE_EXISTS_MAX_PER_MINUTE = 5;

function checkKundeExistsRateLimit(context) {
  const now = Date.now();
  const windowMs = 60000;
  const ip =
    context?.rawRequest?.ip ||
    (context?.rawRequest?.headers &&
      (context.rawRequest.headers["x-forwarded-for"] || "").split(",")[0]?.trim()) ||
    context?.rawRequest?.connection?.remoteAddress ||
    "unknown";
  let entry = _kundeExistsRateLimit.get(ip);
  if (!entry || now - entry.windowStart > windowMs) {
    entry = { count: 0, windowStart: now };
    _kundeExistsRateLimit.set(ip, entry);
  }
  entry.count++;
  if (entry.count > KUNDE_EXISTS_MAX_PER_MINUTE) {
    throw new functions.https.HttpsError(
      "resource-exhausted",
      "Zu viele Anfragen. Bitte später erneut versuchen."
    );
  }
}

function pickBestDocId(docs, searchId) {
  if (!docs || docs.length === 0) return null;
  const withDifferentId = docs.filter((d) => d.id !== searchId);
  if (withDifferentId.length > 0) return withDifferentId[0].id;
  return docs[0].id;
}

async function resolveToDocId(companyId) {
  if (!companyId || typeof companyId !== "string") return null;
  const id = String(companyId).trim().toLowerCase();
  if (!id) return null;
  try {
    const seen = new Set();
    const allDocs = [];
    const [byKundenId, bySubdomain] = await Promise.all([
      db.collection("kunden").where("kundenId", "==", id).limit(5).get(),
      db.collection("kunden").where("subdomain", "==", id).limit(5).get(),
    ]);
    byKundenId.docs.forEach((d) => {
      if (!seen.has(d.id)) {
        seen.add(d.id);
        allDocs.push(d);
      }
    });
    bySubdomain.docs.forEach((d) => {
      if (!seen.has(d.id)) {
        seen.add(d.id);
        allDocs.push(d);
      }
    });
    if (allDocs.length > 0) return pickBestDocId(allDocs, id);
    const doc = await db.collection("kunden").doc(id).get();
    return doc.exists ? doc.id : null;
  } catch (e) {
    console.warn("resolveToDocId:", e.message);
    return null;
  }
}

/**
 * Prüft, ob eine Kunden-ID existiert (ohne Auth).
 * Rückgabe: { exists: boolean, docId?: string }
 */
exports.kundeExists = functions.region("europe-west1").https.onCall(async (data, context) => {
  checkKundeExistsRateLimit(context);
  const companyId = data?.companyId;
  if (!companyId || typeof companyId !== "string") {
    return { exists: false };
  }
  const id = companyId.trim().toLowerCase();
  if (!id) return { exists: false };
  try {
    const seen = new Set();
    const allDocs = [];
    const [byKundenId, bySubdomain] = await Promise.all([
      db.collection("kunden").where("kundenId", "==", id).limit(5).get(),
      db.collection("kunden").where("subdomain", "==", id).limit(5).get(),
    ]);
    byKundenId.docs.forEach((d) => {
      if (!seen.has(d.id)) {
        seen.add(d.id);
        allDocs.push(d);
      }
    });
    bySubdomain.docs.forEach((d) => {
      if (!seen.has(d.id)) {
        seen.add(d.id);
        allDocs.push(d);
      }
    });
    if (allDocs.length > 0) {
      const docId = pickBestDocId(allDocs, id);
      if (docId) return { exists: true, docId };
    }
    const doc = await db.collection("kunden").doc(id).get();
    if (doc.exists) {
      return { exists: true, docId: doc.id };
    }
    return { exists: false };
  } catch (e) {
    console.warn("kundeExists:", e.message);
    return { exists: false };
  }
});

function isGlobalSuperadminEmail(emailRaw) {
  const email = (emailRaw || "").toString().trim().toLowerCase();
  if (!email) return false;
  if (email === "admin@rettbase.de" || email === "admin@rettbase") return true;
  if (email === "112@admin.rettbase.de") return true;
  return false;
}

/**
 * Setzt optionale Custom Claims (companyId) für spätere Storage-Regeln.
 */
async function setCampusAuthClaims(uid, companyId, superadmin) {
  try {
    const user = await admin.auth().getUser(uid);
    const existing = user.customClaims || {};
    const next = { ...existing, companyId: String(companyId || "") };
    if (superadmin) next.campusSuperadmin = true;
    else delete next.campusSuperadmin;
    const same =
      existing.companyId === next.companyId &&
      !!existing.campusSuperadmin === !!next.campusSuperadmin;
    if (same) return;
    await admin.auth().setCustomUserClaims(uid, next);
  } catch (e) {
    console.warn("setCampusAuthClaims:", e.message);
  }
}

/**
 * Legt kunden/{companyId}/users/{uid} an, wenn der Nutzer Mitarbeiter der Firma ist
 * oder technischer Superadmin (E-Mail-Liste).
 */
exports.ensureUsersDoc = functions.region("europe-west1").https.onCall(async (data, context) => {
  if (!context?.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
  }
  const inputCompanyId = (data?.companyId || "").trim();
  if (!inputCompanyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }
  const companyId = (await resolveToDocId(inputCompanyId)) || inputCompanyId.toLowerCase();
  const uid = context.auth.uid;
  const email = (context.auth.token?.email || "").toString();
  const superByEmail = isGlobalSuperadminEmail(email);

  const ref = db.collection("kunden").doc(companyId).collection("users").doc(uid);

  if (superByEmail) {
    await ref.set(
      {
        companyId,
        role: "superadmin",
        email: email.toLowerCase(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    await setCampusAuthClaims(uid, companyId, true);
    return { success: true };
  }

  const byUid = await db
    .collection("kunden")
    .doc(companyId)
    .collection("mitarbeiter")
    .where("uid", "==", uid)
    .limit(1)
    .get();

  if (byUid.empty) {
    const userDoc = await ref.get();
    if (userDoc.exists) {
      await setCampusAuthClaims(uid, companyId, false);
      return { success: true };
    }
    throw new functions.https.HttpsError(
      "permission-denied",
      "Nutzer ist kein Mitarbeiter dieser Firma"
    );
  }

  const m = byUid.docs[0].data();
  await ref.set(
    {
      companyId,
      email: (m.email || email || "").toString(),
      role: (m.role || "user").toString().toLowerCase(),
      mitarbeiterDocId: byUid.docs[0].id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
  await setCampusAuthClaims(uid, companyId, false);
  return { success: true };
});
