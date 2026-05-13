#!/usr/bin/env bash
# Campus Admin-UI lokal im Chrome (nicht lib/main.dart = Verbindungstest).
set -euo pipefail
cd "$(dirname "$0")/.."
exec flutter run -t lib/main_admin.dart -d chrome
