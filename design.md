# RettBase Campus – Brandingfarben

## Primärfarben (Core Identity)

- **Hero Red** (`#E63946`): Ein lebendiges, modernes Rot. Es ist weniger aggressiv als ein reines Signalrot, wirkt aber professionell und dynamisch. Es steht für die Hilfe und den Sanitätsdienst.
- **Deep Slate** (`#2B2D42`): Sehr dunkles Blau-Grau für **Rahmen und Konturen** (Outline-Felder, Trennlinien), **Material-Buttons** (Fläche) und nicht für den Haupttext.
- **Body Text** (`#2B2D24`): Dunkles Grau für **Fließtext**, **AppBar-Typografie** und **Floating-Labels** (`CampusBrand.bodyText` im Theme).

## Sekundärfarben (Akzente und UI)

- **Soft Shell** (`#F8F9FA`): Absolut neutral, modern und erinnert an medizinische Software oder sterile Klinikumgebungen. Es beißt sich garantiert nicht mit dem Rot.
- **Alert Orange** (`#F4A261`): Für wichtige, aber nicht lebenskritische Warnungen oder Markierungen (z. B. „Material nachfüllen“).

## Psychologische Wirkung der Farbkombination

- **Rot:** Signalisiert Wichtigkeit und schnelles Handeln – passend für Sanitäter.
- **Weiß/Grau-Kontraste:** Schaffen Übersichtlichkeit in der Benutzeroberfläche, besonders für Lehrer bei der Dokumentation.

## Umsetzung im Code

Die Konstanten und das Material-3-Theme liegen in `lib/theme/campus_brand.dart` (`CampusBrand`). Für UI-Hinweise im Orange-Ton: `Theme.of(context).colorScheme.secondary` bzw. `CampusBrand.alertOrange`.

**Wichtig:** Die Campus-Oberfläche (App + technische Admin-Oberfläche `lib/main_admin.dart`) nutzt **ausschließlich** diese Tokens über `CampusBrand.theme()` – keine parallelen Farbwelten, kein Mischen mit der Ocean-Professional-Palette der RettBase-Haupt-App (`app/design.md`).

### Buttons (Material)

- **Fläche:** Deep Slate `#2B2D42` (`CampusBrand.deepSlate`).
- **Schrift und Icons auf der Fläche:** Soft Shell `#F8F9FA` (`CampusBrand.softShell`).
- Umsetzung zentral in **`CampusBrand.theme()`** über `filledButtonTheme`, `elevatedButtonTheme`, `outlinedButtonTheme`, `textButtonTheme` und **`floatingActionButtonTheme`** – damit greifen **`FilledButton`** (inkl. `.tonal`), **`OutlinedButton`**, **`TextButton`**, **`ElevatedButton`** und der **FAB** automatisch; neue Buttons ohne eigenes `style` übernehmen dasselbe.

### Technische Admin-Oberfläche (Web / `main_admin.dart`)

- **Kopfzeile:** Überall dieselbe **`AppBar`** mit **Wordmark** (`CampusBrandAssets.wordmark`, Höhe 44; Asset **`assets/brand/campus_logo_wordmark.png`** als **PNG mit Transparenz/RGBA**, kein undifferenziertes Weißfeld) und **zweiter Zeile** (`bodySmall`, `onSurfaceVariant`): Startseite = angemeldete E-Mail; Login = Anmeldung + Projekt-ID; Kundendetail = Schulname (Zurück-Button links). **`CampusBrandAssets.iconMark`** (RB-Kachel) nur in der **mobilen/tablet Campus-App**, nicht in der technischen Admin-Web-Oberfläche. `AppBarTheme.surfaceTintColor` ist **transparent**, damit die weiße Kopfzeile nicht rötlich eingefärbt wird. `toolbarHeight` 88, `titleSpacing` 20 (Detail mit `leading` 12).
- **Reiter:** `TabBar` direkt unter der `AppBar`; Farben und Trennlinie aus `tabBarTheme` / `ColorScheme` in `CampusBrand.theme()`, nicht hardcodiert.
- **Seitenhintergrund:** `scaffoldBackgroundColor` = Soft Shell (`CampusBrand.softShell`).
- **Bestehende Kunden:** Detailansicht: **Kunden-ID**, Stammdaten Schule (`updateCampusCustomer`), Zugang aktiv/inaktiv; pro Schul-Admin (**Rolle `admin`**) **Name und E-Mail bearbeiten** (`updateCampusSchoolAdminProfile` – bei **E-Mail-Wechsel** zwingend **neues Initiales Passwort** in Auth) sowie **Passwort** (`resetCampusSchoolAdminPassword`); Liste aus `getCampusCustomer` → `schoolAdmins`. Kein Anzeige-Feld **Bereich** (`bereich` nur technisch in Firestore).

## Formulare (Textfelder)

- **Outline-Stil (wie Login / Admin):** `TextField` / `TextFormField` mit **`InputDecoration`**, die aus **`CampusBrand.theme()` → `inputDecorationTheme`** kommt (Outline-Rahmen in Deep Slate, weiße Füllfläche, Fokus Hero Red). **Floating Label:** `floatingLabelBehavior: FloatingLabelBehavior.always` – die Beschriftung (`labelText`) liegt **immer an der Rahmenkerbe** (auf dem Rand) in **Body Text** (`#2B2D24`), nicht als Text mitten im leeren Feld.
- **Technische Admin-Oberfläche:** Felder über **`CampusBrand.outlineField(context, labelText: …, helperText: …)`** bauen – das wendet `InputDecoration.applyDefaults` auf das Theme an und entspricht damit exakt dem Login.
- **Beschriftung:** Kurze Feldbezeichnung über **`labelText`**. Längere Hinweise über **`helperText`** (unter dem Rahmen).
- **Nicht:** Nur **`hintText`** ohne **`labelText`** als einzige Erklärung.
