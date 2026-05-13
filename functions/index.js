/**
 * RettBase Campus – Cloud Functions (nur dieses Repository / Projekt rettbase-campus).
 * Enthält: kundeExists, ensureUsersDoc, createCampusCustomer, createCampusCustomerWithAdmin,
 * listCampusCustomers, getCampusCustomer, updateCampusCustomer, setCampusCustomerStatus,
 * resetCampusSchoolAdminPassword, updateCampusSchoolAdminProfile, createCampusSchoolUser.
 *
 * Kein Bezug zu Quellcode oder Deployments der RettBase-Haupt-App.
 */
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/** Firebase Auth (Admin SDK): Fehlercode/Message zuverlässig auslesen. */
function getAdminAuthErrorCode(err) {
  if (!err || typeof err !== "object") return "";
  const c = err.code || err.errorInfo?.code;
  return typeof c === "string" ? c : "";
}

function getAdminAuthErrorMessage(err) {
  if (!err || typeof err !== "object") return String(err);
  return (
    err.errorInfo?.message ||
    err.message ||
    (typeof err.toString === "function" ? err.toString() : "Unbekannter Fehler")
  );
}

/**
 * getUserByEmail: nur user-not-found schlucken; sonst klare Callable-Meldung statt generischem internal.
 */
function rethrowUnlessUserNotFoundFromGetUserByEmail(err) {
  const code = getAdminAuthErrorCode(err);
  if (code === "auth/user-not-found") return;
  const msg = getAdminAuthErrorMessage(err);
  console.warn("getUserByEmail:", code, msg);
  throw new functions.https.HttpsError(
    "failed-precondition",
    code
      ? `E-Mail-Prüfung fehlgeschlagen (${code}). ${msg}`
      : `E-Mail-Prüfung fehlgeschlagen: ${msg}`
  );
}

function mapCreateUserErrorToHttps(err) {
  const code = getAdminAuthErrorCode(err);
  const msg = getAdminAuthErrorMessage(err);
  if (code === "auth/email-already-exists") {
    throw new functions.https.HttpsError(
      "already-exists",
      "Diese E-Mail ist bereits in Firebase Authentication registriert."
    );
  }
  if (code === "auth/invalid-email") {
    throw new functions.https.HttpsError("invalid-argument", "Ungültige E-Mail-Adresse.");
  }
  if (code === "auth/invalid-password" || code === "auth/weak-password") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Passwort lehnt Firebase ab (zu schwach oder ungültig). Bitte mindestens 8 Zeichen, gern länger und mit Buchstaben, Ziffern und Sonderzeichen."
    );
  }
  if (code === "auth/operation-not-allowed") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "E-Mail/Passwort-Anmeldung ist in der Firebase Console unter Authentication → Sign-in method nicht aktiviert."
    );
  }
  console.warn("createUser:", code, msg);
  throw new functions.https.HttpsError(
    "invalid-argument",
    code ? `Nutzer anlegen fehlgeschlagen (${code}): ${msg}` : `Nutzer anlegen fehlgeschlagen: ${msg}`
  );
}

function mapUpdateUserPasswordErrorToHttps(err) {
  const code = getAdminAuthErrorCode(err);
  const msg = getAdminAuthErrorMessage(err);
  if (code === "auth/user-not-found") {
    throw new functions.https.HttpsError(
      "not-found",
      "Firebase-Auth-Nutzer nicht gefunden (UID ungültig oder gelöscht)."
    );
  }
  if (code === "auth/invalid-password" || code === "auth/weak-password") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Passwort lehnt Firebase ab (zu schwach oder ungültig). Bitte mindestens 8 Zeichen, gern länger und mit Buchstaben, Ziffern und Sonderzeichen."
    );
  }
  if (code === "auth/operation-not-allowed") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "E-Mail/Passwort-Anmeldung ist in der Firebase Console unter Authentication → Sign-in method nicht aktiviert."
    );
  }
  console.warn("updateUser password:", code, msg);
  throw new functions.https.HttpsError(
    "invalid-argument",
    code ? `Passwort setzen fehlgeschlagen (${code}): ${msg}` : `Passwort setzen fehlgeschlagen: ${msg}`
  );
}

function mapUpdateUserProfileErrorToHttps(err) {
  const code = getAdminAuthErrorCode(err);
  const msg = getAdminAuthErrorMessage(err);
  if (code === "auth/user-not-found") {
    throw new functions.https.HttpsError(
      "not-found",
      "Firebase-Auth-Nutzer nicht gefunden (UID ungültig oder gelöscht)."
    );
  }
  if (code === "auth/email-already-exists" || code === "auth/email-already-in-use") {
    throw new functions.https.HttpsError(
      "already-exists",
      "Diese E-Mail ist bereits in Firebase Authentication vergeben."
    );
  }
  if (code === "auth/invalid-email") {
    throw new functions.https.HttpsError("invalid-argument", "Ungültige E-Mail-Adresse.");
  }
  if (code === "auth/invalid-password" || code === "auth/weak-password") {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Das Passwort lehnt Firebase ab (zu schwach oder ungültig). Bitte mindestens 8 Zeichen, gern länger und mit Buchstaben, Ziffern und Sonderzeichen."
    );
  }
  if (code === "auth/operation-not-allowed") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "E-Mail/Passwort-Anmeldung ist in der Firebase Console unter Authentication → Sign-in method nicht aktiviert."
    );
  }
  console.warn("updateUser profile:", code, msg);
  throw new functions.https.HttpsError(
    "invalid-argument",
    code ? `Profil speichern fehlgeschlagen (${code}): ${msg}` : `Profil speichern fehlgeschlagen: ${msg}`
  );
}

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

function pickBestDocSnapshot(docs, searchId) {
  if (!docs || docs.length === 0) return null;
  const withDifferentId = docs.filter((d) => d.id !== searchId);
  if (withDifferentId.length > 0) return withDifferentId[0];
  return docs[0];
}

/** true, wenn Login für diesen Kunden erlaubt ist (status !== inactive). */
function customerDocAllowsLogin(docSnap) {
  if (!docSnap || !docSnap.exists) return false;
  const s = String(docSnap.data()?.status ?? "active")
    .trim()
    .toLowerCase();
  return s !== "inactive";
}

async function resolveToDocId(companyId) {
  if (!companyId || typeof companyId !== "string") return null;
  const id = normalizeKundenKey(String(companyId));
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
  const id = normalizeKundenKey(companyId);
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
      const chosen = pickBestDocSnapshot(allDocs, id);
      if (chosen) {
        return {
          exists: true,
          docId: chosen.id,
          loginAllowed: customerDocAllowsLogin(chosen),
        };
      }
    }
    const doc = await db.collection("kunden").doc(id).get();
    if (doc.exists) {
      return {
        exists: true,
        docId: doc.id,
        loginAllowed: customerDocAllowsLogin(doc),
      };
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

/** Kunden-ID / Doc-ID: trim, de-DE Kleinbuchstaben, NFC; erlaubt u. a. äöüß; nur Buchstaben/Ziffern/-/_; kein `/`. */
function normalizeKundenKey(raw) {
  let x = String(raw ?? "")
    .normalize("NFC")
    .trim();
  if (!x) return "";
  x = x.toLocaleLowerCase("de");
  x = x.replace(/[/\\]+/g, "-");
  x = x.replace(/\s+/g, "-");
  x = x.replace(/[^\p{L}\p{N}\-_]/gu, "");
  x = x.replace(/-+/g, "-").replace(/^-+|-+$/g, "");
  return x;
}

/** Maximale UTF-8-Länge für Firestore-Dokument-IDs (Limit 1500 Byte). */
function assertFirestoreDocIdBytes(id, label) {
  const bytes = Buffer.byteLength(id, "utf8");
  if (bytes > 1400) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      `${label}: zu lang (max. ca. 1400 Byte UTF-8).`
    );
  }
  if (id === "." || id === "..") {
    throw new functions.https.HttpsError("invalid-argument", `${label}: ungültige Dokument-ID.`);
  }
  if (id.includes("/")) {
    throw new functions.https.HttpsError("invalid-argument", `${label}: darf kein „/“ enthalten.`);
  }
}

/** Nur primitive Strings für Callable-JSON (Firestore kann Maps/Timestamps enthalten). */
function safeCustomerFieldString(val, fallback = "") {
  if (val == null) return fallback;
  if (typeof val === "string") return val;
  if (typeof val === "number" || typeof val === "boolean") return String(val);
  if (typeof val.toDate === "function") {
    try {
      return val.toDate().toISOString();
    } catch (_) {
      return fallback;
    }
  }
  return fallback;
}

/**
 * Kunden-Dokument laden: exakte ID aus der UI, normalisierte Variante und resolveToDocId.
 */
async function findKundenDocByAnyId(raw) {
  const t = String(raw || "").trim();
  if (!t) return null;
  const tryIds = new Set();
  tryIds.add(t);
  const n = normalizeKundenKey(t);
  if (n) tryIds.add(n);
  try {
    const r = await resolveToDocId(t);
    if (r) tryIds.add(r);
  } catch (e) {
    console.warn("findKundenDocByAnyId resolveToDocId:", e.message);
  }
  for (const id of tryIds) {
    const d = await db.collection("kunden").doc(id).get();
    if (d.exists) return d;
  }
  return null;
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

  const kundenId = normalizeKundenKey(data?.kundenId);
  const name = String(data?.name || "").trim();
  const firestoreDocId = normalizeKundenKey(data?.firestoreDocId || data?.kundenId) || kundenId;
  const subdomain = normalizeKundenKey(data?.subdomain || kundenId) || kundenId;

  if (!kundenId || !name) {
    throw new functions.https.HttpsError("invalid-argument", "kundenId und name sind erforderlich.");
  }
  assertNotReservedCompanyKey(kundenId);
  assertNotReservedCompanyKey(firestoreDocId);
  assertFirestoreDocIdBytes(firestoreDocId, "firestoreDocId");

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
  opt("street");
  opt("houseNumber");
  opt("plz");
  opt("city");

  const street = String(data?.street || "").trim();
  const houseNumber = String(data?.houseNumber || "").trim();
  if (street || houseNumber) {
    payload.address = [street, houseNumber].filter(Boolean).join(" ").trim();
  }
  const plz = String(data?.plz || "").trim();
  const city = String(data?.city || "").trim();
  if (plz || city) {
    payload.zipCity = [plz, city].filter(Boolean).join(" ").trim();
  }

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
    const status = (x.status || "active").toString();
    return {
      id: d.id,
      name: (x.name || d.id).toString(),
      kundenId: (x.kundenId || x.subdomain || d.id).toString(),
      bereich: (x.bereich || "").toString(),
      status,
      active: status.toLowerCase() !== "inactive",
      address: (x.address || "").toString(),
      zipCity: (x.zipCity || "").toString(),
      street: (x.street || "").toString(),
      houseNumber: (x.houseNumber || "").toString(),
      plz: (x.plz || "").toString(),
      city: (x.city || "").toString(),
      phone: (x.phone || "").toString(),
      email: (x.email || "").toString(),
    };
  });
  kunden.sort((a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase(), "de"));
  return { kunden };
});

/**
 * Einzelnes Kundendokument (Admin-UI Detail) – nur technische Admins.
 */
exports.getCampusCustomer = functions.region("europe-west1").https.onCall(async (data, context) => {
  try {
    assertCampusProvisioningAuth(context);
    const input = String(data?.companyId || "").trim();
    if (!input) {
      throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
    }
    let doc = await findKundenDocByAnyId(input);
    if (!doc || !doc.exists) {
      throw new functions.https.HttpsError("not-found", "Kunde nicht gefunden.");
    }
    const x = doc.data() || {};
    const status = safeCustomerFieldString(x.status, "active") || "active";
    const statusLc = status.toLowerCase();
    let schoolAdmins = [];
    try {
      const mitSnap = await doc.ref.collection("mitarbeiter").where("role", "==", "admin").get();
      schoolAdmins = mitSnap.docs
        .map((m) => {
          const md = m.data() || {};
          const uid = safeCustomerFieldString(md.uid, "").trim();
          if (!uid) return null;
          return {
            mitarbeiterDocId: m.id,
            uid,
            email: safeCustomerFieldString(md.email, "").trim().toLowerCase(),
            vorname: safeCustomerFieldString(md.vorname, ""),
            nachname: safeCustomerFieldString(md.nachname, ""),
            role: safeCustomerFieldString(md.role, "admin"),
            active: md.active !== false,
          };
        })
        .filter(Boolean);
    } catch (e) {
      console.warn("getCampusCustomer schoolAdmins:", e.message);
    }
    return {
      id: String(doc.id),
      name: safeCustomerFieldString(x.name, doc.id),
      kundenId: safeCustomerFieldString(x.kundenId, safeCustomerFieldString(x.subdomain, doc.id)),
      subdomain: safeCustomerFieldString(x.subdomain, ""),
      bereich: safeCustomerFieldString(x.bereich, ""),
      status,
      active: statusLc !== "inactive",
      address: safeCustomerFieldString(x.address, ""),
      zipCity: safeCustomerFieldString(x.zipCity, ""),
      street: safeCustomerFieldString(x.street, ""),
      houseNumber: safeCustomerFieldString(x.houseNumber, ""),
      plz: safeCustomerFieldString(x.plz, ""),
      city: safeCustomerFieldString(x.city, ""),
      phone: safeCustomerFieldString(x.phone, ""),
      email: safeCustomerFieldString(x.email, ""),
      schoolAdmins,
    };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    console.error("getCampusCustomer unerwartet:", e);
    throw new functions.https.HttpsError(
      "internal",
      e?.message ? `getCampusCustomer: ${e.message}` : "getCampusCustomer fehlgeschlagen (siehe Functions-Logs)."
    );
  }
});

/**
 * Kunden aktivieren/deaktivieren (Login + Firestore für Nicht-Superadmin gesperrt bei inactive).
 */
exports.setCampusCustomerStatus = functions.region("europe-west1").https.onCall(async (data, context) => {
  assertCampusProvisioningAuth(context);
  const input = String(data?.companyId || "").trim();
  if (!input) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }
  const active = data?.active === true || data?.active === "true";
  const doc = await findKundenDocByAnyId(input);
  if (!doc || !doc.exists) {
    throw new functions.https.HttpsError("not-found", "Kunde nicht gefunden.");
  }
  const ref = doc.ref;
  await ref.set(
    {
      status: active ? "active" : "inactive",
      statusUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      statusUpdatedByUid: context.auth.uid,
    },
    { merge: true }
  );
  return { success: true, companyId: doc.id, active };
});

/**
 * Stammdaten eines bestehenden Kunden aktualisieren (Schule) – nur technische Admins.
 * `kundenId` / Doc-ID werden nicht geändert.
 */
exports.updateCampusCustomer = functions.region("europe-west1").https.onCall(async (data, context) => {
  assertCampusProvisioningAuth(context);
  const input = String(data?.companyId || "").trim();
  if (!input) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }
  const doc = await findKundenDocByAnyId(input);
  if (!doc || !doc.exists) {
    throw new functions.https.HttpsError("not-found", "Kunde nicht gefunden.");
  }
  const name = String(data?.name || "").trim();
  if (!name) {
    throw new functions.https.HttpsError("invalid-argument", "Name der Schule erforderlich.");
  }
  const payload = {
    name,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedByUid: context.auth.uid,
  };
  const optOrDelete = (key, val) => {
    const s = String(val ?? "").trim();
    if (s) payload[key] = s;
    else payload[key] = admin.firestore.FieldValue.delete();
  };
  optOrDelete("street", data?.street);
  optOrDelete("houseNumber", data?.houseNumber);
  optOrDelete("plz", data?.plz);
  optOrDelete("city", data?.city);
  optOrDelete("phone", data?.phone);
  optOrDelete("email", data?.email);

  const street = String(data?.street || "").trim();
  const houseNumber = String(data?.houseNumber || "").trim();
  if (street || houseNumber) {
    payload.address = [street, houseNumber].filter(Boolean).join(" ").trim();
  } else {
    payload.address = admin.firestore.FieldValue.delete();
  }
  const plz = String(data?.plz || "").trim();
  const city = String(data?.city || "").trim();
  if (plz || city) {
    payload.zipCity = [plz, city].filter(Boolean).join(" ").trim();
  } else {
    payload.zipCity = admin.firestore.FieldValue.delete();
  }

  await doc.ref.set(payload, { merge: true });
  return { success: true, companyId: doc.id };
});

/**
 * Neues Passwort für einen Schul-Admin (Rolle admin, Firebase Auth) setzen – nur technische Admins.
 */
exports.resetCampusSchoolAdminPassword = functions.region("europe-west1").https.onCall(async (data, context) => {
  assertCampusProvisioningAuth(context);
  const input = String(data?.companyId || "").trim();
  const targetUid = String(data?.uid || "").trim();
  const newPassword = String(data?.newPassword || "");
  if (!input) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }
  if (!targetUid) {
    throw new functions.https.HttpsError("invalid-argument", "uid des Schul-Admins erforderlich");
  }
  if (newPassword.length < 8) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Neues Passwort: mindestens 8 Zeichen."
    );
  }
  const doc = await findKundenDocByAnyId(input);
  if (!doc || !doc.exists) {
    throw new functions.https.HttpsError("not-found", "Kunde nicht gefunden.");
  }
  const mitSnap = await doc.ref.collection("mitarbeiter").where("uid", "==", targetUid).limit(5).get();
  if (mitSnap.empty) {
    throw new functions.https.HttpsError(
      "not-found",
      "Kein Mitarbeiter-Eintrag mit dieser UID bei diesem Kunden."
    );
  }
  const mitData = mitSnap.docs[0].data() || {};
  const role = String(mitData.role || "").trim().toLowerCase();
  if (role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Passwort-Reset ist nur für Nutzer mit Rolle „admin“ (Schul-Admin) erlaubt."
    );
  }
  try {
    await admin.auth().updateUser(targetUid, { password: newPassword });
  } catch (e) {
    mapUpdateUserPasswordErrorToHttps(e);
  }
  const ts = admin.firestore.FieldValue.serverTimestamp();
  try {
    await mitSnap.docs[0].ref.set({ updatedAt: ts, passwordResetByUid: context.auth.uid }, { merge: true });
  } catch (e) {
    console.warn("resetCampusSchoolAdminPassword mitarbeiter meta:", e.message);
  }
  return { success: true, uid: targetUid };
});

/**
 * Vorname, Nachname und Login-E-Mail eines Schul-Admins (Rolle admin) anpassen – nur technische Admins.
 * Aktualisiert Firebase Auth, kunden/.../mitarbeiter und users/{uid}.
 */
exports.updateCampusSchoolAdminProfile = functions.region("europe-west1").https.onCall(async (data, context) => {
  assertCampusProvisioningAuth(context);
  const input = String(data?.companyId || "").trim();
  const targetUid = String(data?.uid || "").trim();
  const vorname = String(data?.vorname || "").trim();
  const nachname = String(data?.nachname || "").trim();
  const emailRaw = String(data?.email || "").trim().toLowerCase();
  if (!input || !targetUid) {
    throw new functions.https.HttpsError("invalid-argument", "companyId und uid erforderlich.");
  }
  if (!vorname || !nachname) {
    throw new functions.https.HttpsError("invalid-argument", "Vorname und Nachname sind erforderlich.");
  }
  if (!emailRaw || !emailRaw.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Gültige E-Mail erforderlich.");
  }
  const doc = await findKundenDocByAnyId(input);
  if (!doc || !doc.exists) {
    throw new functions.https.HttpsError("not-found", "Kunde nicht gefunden.");
  }
  const st = String(doc.data()?.status ?? "active")
    .trim()
    .toLowerCase();
  if (st === "inactive") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Dieser Kunde ist deaktiviert. Profil kann nicht geändert werden."
    );
  }
  const mitSnap = await doc.ref.collection("mitarbeiter").where("uid", "==", targetUid).limit(5).get();
  if (mitSnap.empty) {
    throw new functions.https.HttpsError(
      "not-found",
      "Kein Mitarbeiter-Eintrag mit dieser UID bei diesem Kunden."
    );
  }
  const mitDoc = mitSnap.docs[0];
  const mitData = mitDoc.data() || {};
  const role = String(mitData.role || "").trim().toLowerCase();
  if (role !== "admin") {
    throw new functions.https.HttpsError(
      "permission-denied",
      "Bearbeiten ist nur für Nutzer mit Rolle „admin“ (Schul-Admin) erlaubt."
    );
  }
  const oldEmail = String(mitData.email || "").trim().toLowerCase();
  const emailChanged = emailRaw !== oldEmail;
  const newPassword = String(data?.newPassword || data?.initialPassword || "").trim();
  if (emailChanged && newPassword.length < 8) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Wenn die E-Mail geändert wird, ist ein neues Initiales Passwort erforderlich (mindestens 8 Zeichen)."
    );
  }

  if (emailChanged) {
    const dupMit = await doc.ref
      .collection("mitarbeiter")
      .where("email", "==", emailRaw)
      .limit(5)
      .get();
    const conflict = dupMit.docs.some((d) => String(d.data()?.uid || "") !== targetUid);
    if (conflict) {
      throw new functions.https.HttpsError(
        "already-exists",
        "Diese E-Mail ist bereits einem anderen Mitarbeiter dieses Kunden zugeordnet."
      );
    }
    try {
      const other = await admin.auth().getUserByEmail(emailRaw);
      if (other.uid !== targetUid) {
        throw new functions.https.HttpsError(
          "already-exists",
          "Diese E-Mail ist bereits in Firebase Authentication vergeben."
        );
      }
    } catch (e) {
      if (e instanceof functions.https.HttpsError) throw e;
      rethrowUnlessUserNotFoundFromGetUserByEmail(e);
    }
  }

  const displayName = [vorname, nachname].filter(Boolean).join(" ").trim();
  const authUpdate = {
    email: emailRaw,
    displayName: displayName || undefined,
  };
  if (emailChanged) {
    authUpdate.password = newPassword;
  }
  try {
    await admin.auth().updateUser(targetUid, authUpdate);
  } catch (e) {
    mapUpdateUserProfileErrorToHttps(e);
  }

  const ts = admin.firestore.FieldValue.serverTimestamp();
  const companyDocId = doc.id;
  const batch = db.batch();
  batch.set(
    mitDoc.ref,
    {
      email: emailRaw,
      vorname,
      nachname,
      updatedAt: ts,
      profileUpdatedByUid: context.auth.uid,
    },
    { merge: true }
  );
  batch.set(
    db.collection("kunden").doc(companyDocId).collection("users").doc(targetUid),
    {
      email: emailRaw,
      updatedAt: ts,
    },
    { merge: true }
  );
  await batch.commit();

  return { success: true, uid: targetUid, email: emailRaw };
});

const SCHOOL_USER_ROLES = new Set(["admin", "leiterssd", "user", "sender"]);

async function createCampusSchoolUserCore(data, context) {
  const inputCompanyId = String(data?.companyId || "").trim();
  if (!inputCompanyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId erforderlich");
  }
  const companyId = (await resolveToDocId(inputCompanyId)) || normalizeKundenKey(inputCompanyId);
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId ungültig oder leer nach Normalisierung.");
  }
  const kundeSnap = await db.collection("kunden").doc(companyId).get();
  if (!kundeSnap.exists) {
    throw new functions.https.HttpsError("not-found", "Kunde nicht gefunden.");
  }
  const st = String(kundeSnap.data()?.status ?? "active")
    .trim()
    .toLowerCase();
  if (st === "inactive") {
    throw new functions.https.HttpsError(
      "failed-precondition",
      "Dieser Kunde ist deaktiviert. Keine neuen Nutzer und kein Login möglich."
    );
  }

  const emailRaw = String(data?.email || "").trim().toLowerCase();
  if (!emailRaw || !emailRaw.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "Gültige E-Mail erforderlich.");
  }
  const password = String(data?.password || "");
  if (password.length < 8) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Passwort mindestens 8 Zeichen."
    );
  }

  let role = String(data?.role || "admin").trim().toLowerCase();
  if (!SCHOOL_USER_ROLES.has(role)) role = "admin";

  const vorname = String(data?.vorname || "").trim() || null;
  const nachname = String(data?.nachname || "").trim() || null;
  const displayName = [vorname, nachname].filter(Boolean).join(" ").trim() || null;

  try {
    await admin.auth().getUserByEmail(emailRaw);
    throw new functions.https.HttpsError(
      "already-exists",
      "Diese E-Mail ist bereits in Firebase Authentication registriert."
    );
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    rethrowUnlessUserNotFoundFromGetUserByEmail(e);
  }

  const dupMit = await db
    .collection("kunden")
    .doc(companyId)
    .collection("mitarbeiter")
    .where("email", "==", emailRaw)
    .limit(1)
    .get();
  if (!dupMit.empty) {
    throw new functions.https.HttpsError(
      "already-exists",
      "Für diese E-Mail existiert bereits ein Mitarbeiter-Eintrag bei diesem Kunden."
    );
  }

  let userRecord;
  try {
    userRecord = await admin.auth().createUser({
      email: emailRaw,
      password,
      displayName: displayName || undefined,
      emailVerified: false,
    });
  } catch (e) {
    mapCreateUserErrorToHttps(e);
  }
  const uid = userRecord.uid;

  const mitRef = db.collection("kunden").doc(companyId).collection("mitarbeiter").doc();
  const mitarbeiterDocId = mitRef.id;
  const usersRef = db.collection("kunden").doc(companyId).collection("users").doc(uid);

  const ts = admin.firestore.FieldValue.serverTimestamp();
  const mitPayload = {
    uid,
    email: emailRaw,
    role,
    active: true,
    createdAt: ts,
    updatedAt: ts,
    creatorUid: context.auth.uid,
  };
  if (vorname) mitPayload.vorname = vorname;
  if (nachname) mitPayload.nachname = nachname;
  const pn = String(data?.personalnummer || "").trim();
  if (pn) mitPayload.personalnummer = pn;

  const batch = db.batch();
  batch.set(mitRef, mitPayload);
  batch.set(
    usersRef,
    {
      companyId,
      email: emailRaw,
      role,
      mitarbeiterDocId,
      updatedAt: ts,
    },
    { merge: true }
  );
  try {
    await batch.commit();
  } catch (e) {
    const detail = e?.message || e?.details || String(e);
    console.warn("createCampusSchoolUser batch:", e?.code, detail);
    try {
      await admin.auth().deleteUser(uid);
    } catch (delErr) {
      console.warn("createCampusSchoolUser rollback deleteUser:", delErr.message);
    }
    throw new functions.https.HttpsError(
      "internal",
      `Mitarbeiter konnte nicht in Firestore gespeichert werden (Auth-Nutzer wurde entfernt): ${detail}`
    );
  }

  await setCampusAuthClaims(uid, companyId, false);

  return {
    success: true,
    uid,
    mitarbeiterDocId,
    companyId,
    email: emailRaw,
    role,
  };
}

/**
 * Legt Firebase-Auth-Nutzer + kunden/{cid}/mitarbeiter + users/{uid} an (Schul-Admin / Mitarbeiter).
 * Nur technische Campus-Admins (wie createCampusCustomer).
 */
exports.createCampusSchoolUser = functions.region("europe-west1").https.onCall(async (data, context) => {
  assertCampusProvisioningAuth(context);
  return createCampusSchoolUserCore(data, context);
});

/**
 * Neuer Kunde inkl. erstem Schul-Admin (Rolle admin) in einem Schritt.
 */
exports.createCampusCustomerWithAdmin = functions.region("europe-west1").https.onCall(async (data, context) => {
  assertCampusProvisioningAuth(context);

  const kundenId = normalizeKundenKey(data?.kundenId);
  const name = String(data?.name || "").trim();
  const firestoreDocId = normalizeKundenKey(data?.firestoreDocId || data?.kundenId) || kundenId;
  const subdomain = normalizeKundenKey(data?.subdomain || kundenId) || kundenId;

  if (!kundenId || !name) {
    throw new functions.https.HttpsError("invalid-argument", "kundenId und name sind erforderlich.");
  }
  assertNotReservedCompanyKey(kundenId);
  assertNotReservedCompanyKey(firestoreDocId);
  assertFirestoreDocIdBytes(firestoreDocId, "firestoreDocId");

  const adminEmail = String(data?.adminEmail || data?.email || "").trim().toLowerCase();
  const adminPassword = String(data?.adminPassword || data?.password || "");
  const adminVorname = String(data?.adminVorname || data?.vorname || "").trim();
  const adminNachname = String(data?.adminNachname || data?.nachname || "").trim();
  if (!adminEmail || !adminEmail.includes("@")) {
    throw new functions.https.HttpsError("invalid-argument", "E-Mail des Schul-Admins erforderlich.");
  }
  if (adminPassword.length < 8) {
    throw new functions.https.HttpsError("invalid-argument", "Initiales Passwort des Admins: mindestens 8 Zeichen.");
  }
  if (!adminVorname || !adminNachname) {
    throw new functions.https.HttpsError(
      "invalid-argument",
      "Vorname und Nachname des Schul-Admins sind erforderlich."
    );
  }

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
  opt("street");
  opt("houseNumber");
  opt("plz");
  opt("city");

  const street = String(data?.street || "").trim();
  const houseNumber = String(data?.houseNumber || "").trim();
  if (street || houseNumber) {
    payload.address = [street, houseNumber].filter(Boolean).join(" ").trim();
  }
  const plz = String(data?.plz || "").trim();
  const city = String(data?.city || "").trim();
  if (plz || city) {
    payload.zipCity = [plz, city].filter(Boolean).join(" ").trim();
  }

  await ref.set(payload);

  try {
    const userRes = await createCampusSchoolUserCore(
      {
        companyId: firestoreDocId,
        email: adminEmail,
        password: adminPassword,
        vorname: adminVorname,
        nachname: adminNachname,
        role: "admin",
      },
      context
    );
    return {
      success: true,
      docId: firestoreDocId,
      kundenId,
      uid: userRes.uid,
      mitarbeiterDocId: userRes.mitarbeiterDocId,
      adminEmail: userRes.email,
    };
  } catch (e) {
    try {
      await ref.delete();
    } catch (delErr) {
      console.warn("createCampusCustomerWithAdmin rollback delete kunde:", delErr.message);
    }
    if (e instanceof functions.https.HttpsError) throw e;
    const msg = e?.message || String(e);
    console.error("createCampusCustomerWithAdmin:", e);
    throw new functions.https.HttpsError(
      "internal",
      msg && msg !== "internal" ? `Kunde anlegen: ${msg}` : "Kunde anlegen: unbekannter Serverfehler (Logs prüfen)."
    );
  }
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
  const companyId = (await resolveToDocId(inputCompanyId)) || normalizeKundenKey(inputCompanyId);
  if (!companyId) {
    throw new functions.https.HttpsError("invalid-argument", "companyId ungültig oder leer nach Normalisierung.");
  }
  const uid = context.auth.uid;
  const email = (context.auth.token?.email || "").toString();
  const superByEmail = isGlobalSuperadminEmail(email);

  const kundeRoot = await db.collection("kunden").doc(companyId).get();
  if (!superByEmail && kundeRoot.exists) {
    const st = String(kundeRoot.data()?.status ?? "active")
      .trim()
      .toLowerCase();
    if (st === "inactive") {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Dieser Kunde wurde deaktiviert. Anmeldung ist nicht möglich."
      );
    }
  }

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
