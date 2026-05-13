#!/usr/bin/env bash
# Baut die Campus-Admin-Flutter-Web-App und deployt sie NUR nach Firebase Hosting
# im Projekt rettbase-campus (Ziel: Hosting-Site rettbase-campus-admin).
# Kein Bezug zur RettBase-Haupt-Web-App (anderes Repo / anderes Firebase-Projekt).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

flutter pub get
flutter build web -t lib/main_admin.dart -o build/web_admin --release

firebase deploy --only "hosting:campus-admin" --project rettbase-campus

echo ""
echo "Fertig. Admin-UI (nach einmaliger Site-Anlage, siehe README):"
echo "  https://rettbase-campus-admin.web.app"
