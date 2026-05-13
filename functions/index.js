/**
 * RettBase Campus – Cloud Functions (nur dieses Repository / Projekt rettbase-campus).
 * Enthält: kundeExists, ensureUsersDoc, createCampusCustomer, listCampusCustomers.
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

/** Nur technische Admins: feste Superadmin-E-Mails oder Custom Claim campusSuperadmin. */
function assertCampusProvisioningAuth(context) {
  if (!context?.auth?.uid) {
    throw new functions.https.HttpsError("unauthenticated", "Benutzer muss authentifiziert sein");
  }
  const email = context.auth.token?.email;
  const claim = context.auth.token?.campusSuperadmin === true;
  if (isGlobalSuperadminEmail(email) || claim) return;
  throw new functions.https.HttpsError(
    "permission-denied",
    "Nur technische Campus-Administratoren dürfen Kunden anlegen oder auflisten."
  );
}

/** Kunden-ID / Doc-ID: Kleinbuchstaben, Ziffern, Bindestrich (wie gängige Client-Normalisierung). */
function normalizeCompanyKey(raw) {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9\-]/g, "");
}

const RESERVED_CUSTOMER_IDS = new Set(["admin", "system", "null", "undefined", "rettbase"]);

function assertNotReservedCompanyKey(id) {
  if (!id || RESERVED_CUSTOMER_IDS.has(id)) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Ungültige oder reservierte Kunden-ID."
    );
  }
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

const CAMPUS_BEREICH = "schulsanitaetsdienst";

/**
 * Legt einen neuen Kunden (Schule) an – nur für Admin-UI / technische Admins.
 * Firestore-Doc-ID standardmäßig = normalisierte kundenId (optional abweichendes firestoreDocId).
 */
exports.createCampusCustomer = functions.region("europe-west1").https.onCall(async (data, context) => {
  assertCampusProvisioningAuth(context);

  const kundenId = normalizeCompanyKey(data?.kundenId);
  const name = String(data?.name || "").trim();
  const firestoreDocId = normalizeCompanyKey(data?.firestoreDocId || data?.kundenId) || kundenId;
  const subdomain = normalizeCompanyKey(data?.subdomain || kundenId) || kundenId;

  if (!kundenId || !name) {
    throw new functions.https.HttpsError("invalid-argument", "kundenId und name sind erforderlich.");
  }
  assertNotReservedCompanyKey(kundenId);
  assertNotReservedCompanyKey(firestoreDocId);

  const dupKundenId = await db.collection("kunden").where("kundenId", "==", kundenId).limit(1).get();
  if (!dupKundenId.empty) {
    throw new functions.https.HttpsError("already-exists", "Diese Kunden-ID wird bereits verwendet.");
  }

  const ref = db.collection("kunden").doc(firestoreDocId);
  const existing = await ref.get();
  if (existing.exists) {
    throw new functions.https.HttpsError("already-exists", "Dieses Firestore-Kundendokument existiert bereits.");
  }

  const payload = {
    name,
    kundenId,
    subdomain,
    bereich: CAMPUS_BEREICH,
    status: "active",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    creatorUid: context.auth.uid,
  };
  const opt = (key) => {
    const v = data?.[key];
    if (v == null) return;
    const s = String(v).trim();
    if (s) payload[key] = s;
  };
  opt("address");
  opt("zipCity");
  opt("phone");
  opt("email");

  await ref.set(payload);
  return { success: true, docId: firestoreDocId, kundenId };
});

/**
 * Liste aller Kunden (kompakt) – für Admin-UI; begrenzt auf 500 Einträge.
 */
exports.listCampusCustomers = functions.region("europe-west1").https.onCall(async (_data, context) => {
  assertCampusProvisioningAuth(context);
  const snap = await db.collection("kunden").limit(500).get();
  const kunden = snap.docs.map((d) => {
    const x = d.data() || {};
    return {
      id: d.id,
      name: (x.name || d.id).toString(),
      kundenId: (x.kundenId || x.subdomain || d.id).toString(),
      bereich: (x.bereich || "").toString(),
      status: (x.status || "active").toString(),
    };
  });
  kunden.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase(), "de"));
  return { kunden };
});

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
