#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/notch.xcodeproj}"
SCHEME="${SCHEME:-notch}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/notch-derived}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/Notch.app"
APP_PATH="$ROOT_DIR/build/Notch.app"
TARGET_PATH="$INSTALL_DIR/Notch.app"

args=(-project "$PROJECT_PATH" -scheme "$SCHEME" -configuration "$CONFIGURATION"
      -destination "$DESTINATION" -derivedDataPath "$DERIVED_DATA_PATH")
if [[ -n "${CLONED_SOURCE_PACKAGES_PATH:-}" ]]; then
  args+=(-clonedSourcePackagesDirPath "$CLONED_SOURCE_PACKAGES_PATH")
fi
xcodebuild "${args[@]}" CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
  DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}" build
[[ -f "$BUILT_APP_PATH/Contents/MacOS/notch" ]] || { echo "Built app not found: $BUILT_APP_PATH" >&2; exit 1; }

# Always export a complete, clean bundle at the same public build path.
EXPORT_STAGE="$(mktemp -d "$ROOT_DIR/build/.notch-export.XXXXXX")"
trap 'rm -rf "$EXPORT_STAGE"' EXIT
ditto "$BUILT_APP_PATH" "$EXPORT_STAGE/Notch.app"
if [[ -e "$APP_PATH" ]]; then
  mv "$APP_PATH" "$EXPORT_STAGE/previous.app"
fi
if ! mv "$EXPORT_STAGE/Notch.app" "$APP_PATH"; then
  [[ ! -e "$EXPORT_STAGE/previous.app" ]] || mv "$EXPORT_STAGE/previous.app" "$APP_PATH"
  exit 1
fi
rm -rf "$EXPORT_STAGE"
trap - EXIT

if [[ "${INSTALL_APP:-YES}" != YES ]]; then
  echo "Built: $APP_PATH"
  exit 0
fi
if pgrep -x notch >/dev/null || pgrep -x DynamicNotch >/dev/null; then
  echo "Built: $APP_PATH. Quit running Notch copies before installing." >&2
  exit 1
fi
if [[ ! -w "$INSTALL_DIR" || ( -e "$TARGET_PATH" && ! -O "$TARGET_PATH" ) ]]; then
  echo "Built successfully. macOS administrator approval is required to replace $TARGET_PATH." >&2
  echo "Create an installer: APP_PATH=\"$APP_PATH\" bash \"$ROOT_DIR/build_pkg.sh\"" >&2
  exit 1
fi

# Stage completely before replacing; never recursively delete an installed app.
STAGING_DIR="$(mktemp -d "$INSTALL_DIR/.notch-install.XXXXXX")"
trap 'rmdir "$STAGING_DIR" 2>/dev/null || true' EXIT
ditto "$APP_PATH" "$STAGING_DIR/Notch.app"
BACKUP=""
if [[ -e "$TARGET_PATH" ]]; then
  BACKUP="$ROOT_DIR/build/previous-$(date +%Y%m%d-%H%M%S)/Notch.app"
  mkdir -p "$(dirname "$BACKUP")"
  mv "$TARGET_PATH" "$BACKUP"
fi
if ! mv "$STAGING_DIR/Notch.app" "$TARGET_PATH"; then
  [[ -z "$BACKUP" ]] || mv "$BACKUP" "$TARGET_PATH"
  echo "Installation failed; previous app restored." >&2
  exit 1
fi
echo "Installed: $TARGET_PATH (left closed)"
