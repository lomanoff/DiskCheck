#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "→ Generating app icon…"
swift "$ROOT/Scripts/generate_app_icon.swift" "$ROOT/DiskCheck/Assets.xcassets/AppIcon.appiconset"

echo "→ Regenerating Xcode project…"
xcodegen generate

SCHEME="DiskCheck"
ARCHIVE_PATH="$ROOT/build/DiskCheck.xcarchive"
EXPORT_PATH="$ROOT/build/AppStore"

rm -rf "$ROOT/build"
mkdir -p "$ROOT/build"

echo "→ Archiving (Release)…"
xcodebuild archive \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Automatic \
  | xcpretty || true

echo "→ Exporting for App Store Connect…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$ROOT/Config/ExportOptions.plist" \
  | xcpretty || true

echo ""
echo "✓ Готово. Загрузите пакет из:"
echo "  $EXPORT_PATH"
echo ""
echo "Или откройте Xcode → Product → Archive и загрузите через Organizer."
