# RettBase Campus (Schulsanitätsdienst)

Eigenständige Flutter-App für das Firebase-Projekt **rettbase-campus** (Anzeigename in der Console: RettBase-Campus).

## Voraussetzungen

- Flutter SDK (wie Haupt-App)
- [Firebase CLI](https://firebase.google.com/docs/cli) mit Login (`firebase login`)
- In der **Firebase Console** → Authentication → **E-Mail/Passwort** aktivieren (für Login und „Konto anlegen“ in der Entwicklung)

## Firestore Security Rules

Die Regeln liegen in `firestore.rules` (Collection `campus_connect_selftest`: nur eigenes Dokument `docId == request.auth.uid`).

Deployment aus diesem Ordner (Projekt explizit setzen, falls die CLI sonst ein anderes Repo-Root wählt):

```bash
cd rettbase_campus
firebase deploy --only firestore:rules --project rettbase-campus
```

Optional dauerhaft für dieses Verzeichnis:

```bash
firebase use rettbase-campus
```

## App starten

```bash
cd rettbase_campus
flutter pub get
flutter run
```

Erster Ablauf: Konto anlegen oder anmelden, dann **„Firestore testen“** – bei erfolgreichem Schreiben/Lesen ist die Kette App ↔ Auth ↔ Firestore in **rettbase-campus** verifiziert.

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
