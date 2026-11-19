#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${APP_PATH:-$ROOT_DIR/build/Notch.app}"
OUTPUT_PATH="${OUTPUT_PATH:-$ROOT_DIR/build/notch-installer.pkg}"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notch-pkg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

if [[ ! -f "$APP_PATH/Contents/Info.plist" ]]; then
  echo "App not found: $APP_PATH. Build notch first, or set APP_PATH." >&2
  exit 1
fi

mkdir -p "$STAGING_DIR/root" "$STAGING_DIR/packages" "$STAGING_DIR/resources"
ditto "$APP_PATH" "$STAGING_DIR/root/Notch.app"

pkgbuild --analyze --root "$STAGING_DIR/root" "$STAGING_DIR/components.plist"

python3 - "$STAGING_DIR" <<'PY'
import pathlib
import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET

staging = pathlib.Path(sys.argv[1])
app = staging / "root/Notch.app"
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if info.get("CFBundleIdentifier") != "in.infynite.notch":
    raise SystemExit("Refusing to package an unexpected application.")
if info.get("CFBundleName") != "Notch" or info.get("CFBundleExecutable") != "notch":
    raise SystemExit("Expected the current, renamed notch build.")

component_file = staging / "components.plist"
components = plistlib.loads(component_file.read_bytes())
for component in components:
    # Otherwise Installer can find a matching bundle in a build directory and
    # update that copy instead of installing into /Applications.
    component["BundleIsRelocatable"] = False
    component["BundleIsVersionChecked"] = False
    component["BundleHasStrictIdentifier"] = True
    component["BundleOverwriteAction"] = "upgrade"
component_file.write_bytes(plistlib.dumps(components))

version = info["CFBundleShortVersionString"]
identifier = "in.infynite.notch.pkg"
architectures = subprocess.check_output(
    ["/usr/bin/lipo", "-archs", str(app / "Contents/MacOS/notch")], text=True
).strip().split()

distribution = ET.Element("installer-gui-script", minSpecVersion="2")
ET.SubElement(distribution, "title").text = "Notch"
ET.SubElement(distribution, "options", {
    "customize": "never", "require-scripts": "false",
    "hostArchitectures": ",".join(architectures),
})
ET.SubElement(distribution, "domains", {
    "enable_localSystem": "true", "enable_currentUserHome": "false", "enable_anywhere": "false",
})
check = ET.SubElement(distribution, "volume-check")
versions = ET.SubElement(check, "allowed-os-versions")
ET.SubElement(versions, "os-version", min=info.get("LSMinimumSystemVersion", "14.0"))
ET.SubElement(distribution, "welcome", file="welcome.html")
ET.SubElement(distribution, "conclusion", file="conclusion.html")
outline = ET.SubElement(distribution, "choices-outline")
ET.SubElement(outline, "line", choice="notch")
choice = ET.SubElement(distribution, "choice", id="notch", visible="false", title="notch")
ET.SubElement(choice, "pkg-ref", id=identifier)
ET.SubElement(distribution, "pkg-ref", {
    "id": identifier, "version": version, "onConclusion": "none",
}).text = "notch-component.pkg"
ET.indent(distribution)
ET.ElementTree(distribution).write(
    staging / "Distribution.xml", encoding="utf-8", xml_declaration=True
)
(staging / "version").write_text(version)

style = "<style>body{font:14px -apple-system,BlinkMacSystemFont,sans-serif;padding:24px;line-height:1.6}h1{font-size:32px;letter-spacing:-1px}p{max-width:480px}</style>"
(staging / "resources/welcome.html").write_text(
    "<!doctype html><html><head><meta charset='utf-8'>" + style +
    "</head><body><h1>Notch</h1><p>This installer puts Notch by infynite in your Applications folder."
    "</p><p>Quit any running copy of notch before continuing. An existing "
    "/Applications/Notch.app will be replaced. This rebrand starts with fresh settings; old preferences are left untouched."
    "</p><p>No terminal commands or drag-and-drop steps are needed.</p></body></html>"
)
(staging / "resources/conclusion.html").write_text(
    "<!doctype html><html><head><meta charset='utf-8'>" + style +
    "</head><body><h1>You're ready.</h1><p>Open <b>Notch</b> from Applications "
    "or Spotlight.</p><p>Use the menu-bar icon &rarr; <b>AI Agents&hellip;</b> "
    "to connect your coding agents. Installation does not modify their settings."
    "</p></body></html>"
)
PY

VERSION="$(cat "$STAGING_DIR/version")"
pkgbuild \
  --root "$STAGING_DIR/root" \
  --component-plist "$STAGING_DIR/components.plist" \
  --install-location /Applications \
  --identifier in.infynite.notch.pkg \
  --version "$VERSION" \
  --ownership recommended \
  "$STAGING_DIR/packages/notch-component.pkg"

mkdir -p "$(dirname "$OUTPUT_PATH")"
productbuild \
  --distribution "$STAGING_DIR/Distribution.xml" \
  --resources "$STAGING_DIR/resources" \
  --package-path "$STAGING_DIR/packages" \
  "$OUTPUT_PATH"

echo "Installer created: $OUTPUT_PATH"
echo "Local unsigned installer; Developer ID signing/notarization is needed for public distribution."
