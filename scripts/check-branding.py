#!/usr/bin/env python3
"""Source-only rebrand checks. Legal attribution and legacy detection are intentional."""
import json
import plistlib
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
errors = []
def check(condition, message):
    if not condition:
        errors.append(message)

project = (root / "notch.xcodeproj/project.pbxproj").read_text()
check(project.count("PRODUCT_BUNDLE_IDENTIFIER = in.infynite.notch;") == 2, "App identity must be in.infynite.notch")
check(project.count("PRODUCT_MODULE_NAME = notch;") == 2, "Swift module must be lowercase notch")
check(project.count("PRODUCT_NAME = Notch;") == 2, "App bundle must be Notch.app")
check("WZHZ6LB2F6" not in project, "Upstream signing team is still configured")
check('knownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,' in project, "Only English/Base regions should be declared")
info = plistlib.loads((root / "notch/Application/Info.plist").read_bytes())
check(info["CFBundleDisplayName"] == "Notch", "Display name must be Notch")
check(info["SUFeedURL"] == "https://github.com/infynitehq/notch/releases/latest/download/appcast.xml", "Unexpected update feed")
check(info["SUPublicEDKey"] == "ga0m4nh4WzDBjNPySlqj/OTe9kqnL0sHLOK+hk3NLm8=", "Unexpected update public key")
for path in (root / "notch/Resources/Localization").glob("*.xcstrings"):
    data = json.loads(path.read_text())
    check(data["sourceLanguage"] == "en", f"{path.name}: source language is not English")
    for key, value in data["strings"].items():
        check(set(value.get("localizations", {})) <= {"en"}, f"{path.name}: non-English translation in {key}")
        check(not key.startswith("settings.language."), f"Obsolete language selector: {key}")

allowed = {
    "notch/Application/AppIdentity.swift",
    "notch/Features/Settings/Application/Views/AboutAppSettingsView.swift",
    "notch/Resources/Localization/InfoPlist.xcstrings",
}
for directory in ("notch", "notchtests", "notchuitests", "notch.xcodeproj"):
    for path in (root / directory).rglob("*"):
        if not path.is_file() or "MediaRemoteAdapter.framework" in path.parts or path.suffix not in (".swift", ".mjs", ".json", ".pbxproj", ".xcscheme"):
            continue
        relative = path.relative_to(root).as_posix()
        text = path.read_text()
        if relative not in allowed:
            check(not re.search(r"dynamic.?notch|com\.Jackson|jackson-storm|Dynamic_Notch", text, re.I), f"Legacy product reference: {relative}")
        check("com.notch." not in text, f"Unscoped app identifier in {relative}")
check(not (root / "notch/Resources/Assets.xcassets/language").exists(), "Unused language flags remain")
if errors:
    raise SystemExit("\n".join(errors))
print("Branding checks passed: Notch / infynite, lowercase internal identity, English only, dedicated update trust.")
