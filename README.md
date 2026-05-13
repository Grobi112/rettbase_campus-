# RettBase Campus (Schulsanitätsdienst)

Eigenständige Flutter-App für das Firebase-Projekt **rettbase-campus** (Anzeigename in der Console: RettBase-Campus).

## Voraussetzungen

- Flutter SDK (wie Haupt-App)
- [Firebase CLI](https://firebase.google.com/docs/cli) mit Login (`firebase login`)
- In der **Firebase Console** → Authentication → **E-Mail/Passwort** aktivieren (für Login und „Konto anlegen“ in der Entwicklung)

## Firestore-Datenmodell (kompatibel zur RettBase-Haupt-App)

Ziel ist dieselbe Struktur unter `kunden/{companyDocId}/…`, damit SSD-Code portierbar bleibt:

| Pfad | Zweck |
|------|--------|
| `kunden/{id}` | Stammdaten der Schule/Firma |
| `kunden/{id}/users/{uid}` | Rolle + `companyId` (Zuordnung Firebase-Auth → Kunde); **muss** existieren, damit Regeln Zugriff gewähren |
| `kunden/{id}/mitarbeiter/{mitarbeiterId}` | Mitarbeiter inkl. ggf. `uid` |
| `kunden/{id}/modules/{moduleId}` | Modul-Schalter (optional) |
| `kunden/{id}/ssd_dienstplan_*` | Dienstplan-Labels / Ausnahmen |
| `kunden/{id}/ssdPublicAlarmOrte/{token}` | Öffentliche Alarm-Orte (Verwaltung) |
| `kunden/{id}/einsatzprotokoll-ssd/{…}` | Einsatzprotokoll SSD |
| `kunden/{id}/alarmierung-nfs/{…}` | Alarmierung (wie RettBase) |
| `kunden/{id}/alarmierung-nfs-zähler/{jahr}` | Laufende Nummern (Umlaut im Collection-Namen) |
| `kunden/{id}/settings/…` | u. a. `einsatzprotokoll-ssd`, `material_check` (letzteres strenger) |
| `campus_connect_selftest/{uid}` | Entwickler-Selbsttest |

Weitere Collections für spätere Features **explizit** in `firestore.rules` ergänzen (kein generisches `/{document=**}`, damit Mitarbeiter-Updates nicht aufgeweicht werden).

**Technischer Superadmin (Admin-E-Mail / Claim `campusSuperadmin`):** Hat für **jedes** `kunden/{kundenId}`-Subpfad Zugriff, **ohne** dass `kunden/.../users/{uid}` existieren muss (`canAccessCompany` enthält `isSuperadmin()`). So kannst du dich mit der technischen Admin-Adresse in **jeden** Kundenkontext einloggen (App übergibt `companyId` / Kunden-Doc-ID), solange die Regeln deployed sind und die E-Mail bzw. der Claim zur Definition von `isSuperadmin()` passt.

**Erster Login (Schul-Nutzer) in der Campus-App (`lib/main.dart`):** Die App fragt **einmalig** die **Kunden-ID** ab (wird lokal gespeichert; Prüfung per Callable **`kundeExists`**). Anschließend **E-Mail und Passwort**. Nach erfolgreicher Anmeldung ruft die App **`ensureUsersDoc`** mit dieser Kunden-ID auf, damit `kunden/.../users/{uid}` und Firestore-Zugriff passen.

**Provisioning durch technischen Admin:** Kunde per **`createCampusCustomer`**, Nutzer per **`createCampusSchoolUser`** (Firebase Auth + `mitarbeiter` + `users`). Danach kann der Schulnutzer den App-Flow mit seiner Kunden-ID nutzen.

## Firestore Security Rules

Datei `firestore.rules`: Zugriff auf `kunden/*` nur, wenn `kunden/{id}/users/{auth.uid}` existiert (oder Superadmin-E-Mail wie in RettBase). Explizite Regeln u. a. für `mitarbeiter`, `users`, `modules`, Dienstplan-SSD, `einsatzprotokoll-ssd`, Alarmierung, `settings`, `ssd_share_pins` (nur Server), `fcmTokens`. Collection `alarmierung-nfs-zähler` per Variable + Stringvergleich (Umlaut im Namen).

Deployment aus diesem Ordner (Projekt explizit setzen, falls die CLI sonst ein anderes Repo-Root wählt):

```bash
cd rettbase_campus
firebase deploy --only firestore:rules --project rettbase-campus
```

Optional dauerhaft für dieses Verzeichnis:

```bash
firebase use rettbase-campus
```

## Cloud Functions (eigenes Paket `functions/`)

Runtime laut Firebase: **Node 22** (1st Gen). In `functions/package.json` muss **`engines.node` exakt `22`** (oder `20` / `24`) stehen – **keine** Bereiche wie `>=22`, sonst bricht `firebase deploy` ab. Abhängigkeiten: **`firebase-functions` 7.x** (`require("firebase-functions/v1")`), **`firebase-admin` 13.x**. Lokal am besten **Node 22** (`nvm use 22`), damit `npm install` ohne Engine-Warnung läuft.

Callable Functions (Region **europe-west1**):

| Name | Zweck |
|------|--------|
| `kundeExists` | Prüft Kunden-ID / Subdomain → `docId` (ohne Auth, mit Rate-Limit) |
| `ensureUsersDoc` | Legt `kunden/{docId}/users/{uid}` an (nach Login), wenn Mitarbeiter-Eintrag mit `uid` existiert oder technische Superadmin-E-Mail |
| `createCampusCustomer` | **Admin-UI:** neuen Kunden (`kunden/{doc}`) anlegen – nur technische Admins (siehe unten) |
| `createCampusCustomerWithAdmin` | **Admin-UI:** Kunde + erster Schul-Admin in einem Schritt – nur technische Admins |
| `listCampusCustomers` | **Admin-UI:** Kundenliste (max. 500, sortiert nach Name) – nur technische Admins |
| `getCampusCustomer` | **Admin-UI:** Kunden-Detail inkl. Liste `schoolAdmins` (Rolle `admin`) – nur technische Admins |
| `updateCampusCustomer` | **Admin-UI:** Stammdaten eines bestehenden Kunden ändern (`kundenId` / Doc-ID unverändert) – nur technische Admins |
| `setCampusCustomerStatus` | **Admin-UI:** Kunde aktiv / inaktiv – nur technische Admins |
| `resetCampusSchoolAdminPassword` | **Admin-UI:** neues Firebase-Passwort für einen Schul-Admin (`mitarbeiter`, Rolle `admin`) – nur technische Admins |
| `updateCampusSchoolAdminProfile` | **Admin-UI:** Vorname, Nachname und Login-E-Mail eines Schul-Admins (`admin`) anpassen (Auth + `mitarbeiter` + `users`) – nur technische Admins |
| `createCampusSchoolUser` | **Admin-UI:** Firebase Auth + `mitarbeiter` + `users/{uid}` für einen Kunden – nur technische Admins |

### Wer darf die Admin-Callables (`createCampusCustomer`, `listCampusCustomers`, `getCampusCustomer`, `updateCampusCustomer`, `setCampusCustomerStatus`, `resetCampusSchoolAdminPassword`, `updateCampusSchoolAdminProfile`, `createCampusSchoolUser`, `createCampusCustomerWithAdmin`)?

- Firebase-Auth mit E-Mail **admin@rettbase.de**, **admin@rettbase** oder **112@admin.rettbase.de**, **oder**
- Custom Claim **`campusSuperadmin: true`** (wird bei `ensureUsersDoc` für Superadmin-E-Mails mit gesetzt).

### Payload `createCampusCustomer`

| Feld | Pflicht | Beschreibung |
|------|---------|----------------|
| `kundenId` | ja | Login-Kennung: nach Normalisierung u. a. **äöüß**, Unicode-Buchstaben, Ziffern, `-`, `_` (kein `/`; max. UTF-8-Länge für Firestore-Doc-ID siehe Function) |
| `name` | ja | Anzeigename der Schule |
| `firestoreDocId` | nein | Dokument-ID unter `kunden/` (Standard = normalisierte `kundenId`) |
| `subdomain` | nein | Standard = `kundenId` |
| `address`, `zipCity`, `phone`, `email` | nein | optionale Stammdaten |

Antwort: `{ success: true, docId, kundenId }`. Feld **`bereich`** ist immer **`schulsanitaetsdienst`**. Doppelte `kundenId` oder bestehendes Doc → Fehler `already-exists`.

### Payload `createCampusSchoolUser`

| Feld | Pflicht | Beschreibung |
|------|---------|--------------|
| `companyId` | ja | Firestore-Dokument-ID des Kunden (oder auflösbar wie bei `ensureUsersDoc`) |
| `email` | ja | E-Mail des neuen Nutzers (noch nicht in Firebase Auth) |
| `password` | ja | Initiales Passwort (mindestens 8 Zeichen) |
| `role` | nein | `admin` (Standard), `leiterssd`, `user` oder `sender` |
| `vorname`, `nachname`, `personalnummer` | nein | Stammdaten fürs Mitarbeiter-Dokument |

Antwort: `{ success, uid, mitarbeiterDocId, companyId, email, role }`. E-Mail bereits in Auth oder Mitarbeiter mit gleicher E-Mail beim Kunden → `already-exists`.

### Payload `updateCampusCustomer`

| Feld | Pflicht | Beschreibung |
|------|---------|----------------|
| `companyId` | ja | Firestore-Dokument-ID des Kunden (oder auflösbar wie bei `getCampusCustomer`) |
| `name` | ja | Name der Schule |
| `street`, `houseNumber`, `plz`, `city`, `phone`, `email` | nein | Leere Felder entfernen die jeweiligen Keys bzw. abgeleitete `address` / `zipCity` im Dokument |

### Payload `updateCampusSchoolAdminProfile`

| Feld | Pflicht | Beschreibung |
|------|---------|----------------|
| `companyId` | ja | wie bei `getCampusCustomer` |
| `uid` | ja | Firebase-Auth-UID des Schul-Admins (`mitarbeiter`, Rolle `admin`) |
| `vorname`, `nachname` | ja | Anzeige / `displayName` in Auth |
| `email` | ja | Login-E-Mail (bei **Änderung** gegenüber bisherigem Wert zusätzlich `newPassword` nötig, siehe unten) |
| `newPassword` | **nur bei E-Mail-Wechsel** | Mindestens 8 Zeichen; setzt in Firebase Auth das neue Passwort gemeinsam mit der neuen E-Mail |

### Payload `resetCampusSchoolAdminPassword`

| Feld | Pflicht | Beschreibung |
|------|---------|----------------|
| `companyId` | ja | wie oben |
| `uid` | ja | Firebase-Auth-UID des Schul-Admins (muss in `kunden/…/mitarbeiter` mit Rolle `admin` vorkommen) |
| `newPassword` | ja | mindestens 8 Zeichen (Firebase-Regeln) |

Rolle **`sender`**: in den Firestore-Regeln wie **`user`** – Zugriff über `canAccessCompany`, aber **keine** Mitarbeiter-/User-Verwaltung und keine erweiterten Admin-/LeiterSSD-Rechte (Dienstplan schreiben, Alarmorte verwalten usw. bleiben `admin` / `leiterssd` vorbehalten).

**Deploy der Functions** (im Ordner `rettbase_campus`):

```bash
cd rettbase_campus/functions && npm install
cd ..
firebase deploy --only functions --project rettbase-campus
```

Falls die CLI nach einer **Artifact-Cleanup-Policy** fragt: einmalig  
`firebase deploy --only functions --project rettbase-campus --force`  
ausführen. **Voraussetzung:** Firebase-Projekt **Blaze**. Der Quellcode unter `functions/` ist nur für RettBase Campus (keine Abhängigkeit von der Haupt-App `app/functions`).

### Admin-Oberfläche im Browser (nur Projekt **rettbase-campus**)

Die Admin-UI ist eine **eigenständige Flutter-Web-Build** (`lib/main_admin.dart`). Sie wird auf eine **eigene Firebase-Hosting-Site** im Campus-Projekt deployt – **nicht** auf die Hosting-Konfiguration der RettBase-Haupt-App (anderes Firebase-Projekt / anderes Repo).

**Einmalig:** Zusätzliche Hosting-Site anlegen (falls noch nicht vorhanden):

```bash
cd rettbase_campus
firebase hosting:sites:create rettbase-campus-admin --project rettbase-campus
```

Falls die CLI meldet, die Site existiert bereits, ist nichts zu tun.

Das Ziel **`campus-admin`** in `firebase.json` / `.firebaserc` zeigt auf die Site-ID **`rettbase-campus-admin`**. URL nach Deploy typischerweise:

`https://rettbase-campus-admin.web.app`

**Build + Deploy:**

```bash
cd rettbase_campus
./scripts/deploy_campus_admin_web.sh
```

Manuell entspricht das:

```bash
flutter pub get
flutter build web -t lib/main_admin.dart -o build/web_admin --release
firebase deploy --only hosting:campus-admin --project rettbase-campus
```

**Lokal ohne Hosting:** weiterhin `flutter run -t lib/main_admin.dart -d chrome`.

**Authentication:** Unter Firebase Console → Authentication → Einstellungen → **Autorisierte Domains** sollte die Hosting-Domain (z. B. `rettbase-campus-admin.web.app`) stehen – wird bei Hosting oft automatisch ergänzt; bei Login-Problemen prüfen.

Dort: Kunde anlegen, ggf. Kunden-ID aus Liste **Übernehmen**, Nutzer mit E-Mail/Passwort und Rolle anlegen.

## App starten

**Campus-App** (`lib/main.dart`): gleicher Ablauf wie in der **Haupt-App** – SharedPreferences **`rettbase_company_configured`**, **`rettbase_company_id`**, **`rettbase_subdomain`**; beim Start **`kundeExists`** (Region `europe-west1`); nach gültiger Kunden-ID **`signOut`** und Login mit E-Mail/Passwort; nach Login **`ensureUsersDoc`**. Ältere Installation mit `rettbase_campus_kunden_id` wird einmalig migriert.

**Admin-UI** (`lib/main_admin.dart`): Kunden anlegen, Nutzer mit Rolle – lokal z. B.:

```bash
cd rettbase_campus
./scripts/run_admin_chrome.sh
```

(entspricht `flutter run -t lib/main_admin.dart -d chrome`)

```bash
cd rettbase_campus
flutter pub get
flutter run
```

Admin-UI im Browser: siehe **„Admin-Oberfläche im Browser“** (`scripts/deploy_campus_admin_web.sh`). Lokal: `./scripts/run_admin_chrome.sh` oder `flutter run -t lib/main_admin.dart -d chrome`.

Erster Ablauf: **Kunden-ID** einmal eingeben (wird gespeichert), dann Konto anlegen oder anmelden; die App ruft **`ensureUsersDoc`** auf und du kannst **„Firestore testen“** nutzen – damit ist App ↔ Auth ↔ Firestore für den gewählten Kunden verifiziert. **Kunden-ID ändern** (App-Leiste) löscht die gespeicherte ID und meldet ab.

## Konfiguration neu erzeugen

Falls Apps in Firebase neu angelegt werden:

```bash
dart pub global run flutterfire_cli:flutterfire configure --project=rettbase-campus --yes --platforms=android,ios,web --out=lib/firebase_options.dart
```

## Eigenes GitHub-Repository

1. Auf GitHub ein **leeres** Repository anlegen (z. B. `RettBase-Campus`).
2. Nur diesen Ordner als Root pushen, z. B.:

```bash
cd rettbase_campus
git init
git add .
git commit -m "Initial RettBase Campus bootstrap"
git branch -M main
git remote add origin https://github.com/Grobi112/RettBase-Campus.git
git push -u origin main
```

(Passe `origin` an euer echtes Repo an.)

Solange der Ordner noch im **RettBase**-Mono-Repo liegt, bleibt er ein normaler Unterordner – ihr könnt ihn später mit `git filter-repo` oder manuellem Export auch sauber auskoppeln.
