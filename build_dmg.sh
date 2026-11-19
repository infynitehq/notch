#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/notch.xcodeproj}"
SCHEME="${SCHEME:-notch}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/notch-derived}"
CLONED_SOURCE_PACKAGES_PATH="${CLONED_SOURCE_PACKAGES_PATH:-}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"

APP_NAME="${APP_NAME:-Notch.app}"
VOLUME_NAME="${VOLUME_NAME:-Notch}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/build}"
DMG_NAME="${DMG_NAME:-notch.dmg}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notch-dmg.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

# Optionally wrap an existing installer instead of building a drag-to-install image.
# Example: INSTALLER_PATH="$PWD/build/notch-installer.pkg" OUTPUT_DIR="$PWD/build" bash build_dmg.sh
if [[ -n "${INSTALLER_PATH:-}" ]]; then
  if [[ ! -f "$INSTALLER_PATH" ]]; then
    echo "Installer not found: $INSTALLER_PATH" >&2
    exit 1
  fi
  ditto "$INSTALLER_PATH" "$STAGING_DIR/Install Notch.pkg"
  cat > "$STAGING_DIR/Read Me.txt" <<'EOF'
Notch by infynite

1. Quit old Notch copies if running.
2. Double-click "Install Notch.pkg".
3. Follow the macOS Installer steps.
4. Open Notch from Applications or Spotlight.

The installer replaces /Applications/Notch.app.
This rebrand starts with fresh settings and leaves legacy preferences untouched.
No dragging or terminal commands are needed.

This is a local unsigned build, not a notarized public release.
Only use Open Anyway in System Settings > Privacy & Security if you trust its source.
EOF
  mkdir -p "$OUTPUT_DIR"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
  echo "Installer disk image created: $DMG_PATH"
  exit 0
fi

echo "Resolving Swift packages..."
if [[ -n "$CLONED_SOURCE_PACKAGES_PATH" ]]; then
  xcodebuild \
    -resolvePackageDependencies \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_PATH"
else
  xcodebuild \
    -resolvePackageDependencies \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME"
fi

echo "Building $APP_NAME ($CONFIGURATION)..."
if [[ -n "$CLONED_SOURCE_PACKAGES_PATH" ]]; then
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_PATH" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    build
else
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    build
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build finished, but app was not found at: $APP_PATH" >&2
  exit 1
fi

echo "Staging DMG contents..."
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

mkdir -p "$OUTPUT_DIR"
rm -f "$DMG_PATH"

echo "Creating DMG: $DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created: $DMG_PATH"
