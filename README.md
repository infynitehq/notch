# Notch

**A little space. A lot happening.** A native macOS notch companion by **infynite**.

Notch turns the top center of your display into a live surface for music,
timers, downloads, connectivity, hardware controls, and coding-agent status.
Displays without a camera notch use a floating capsule.

## Getting started

1. Install **Notch.app** in Applications and open it once.
2. The welcome window explains the overlay and menu-bar controls.
3. **Left-click the rectangle icon in the top-right menu bar → Settings**.
   Right-clicking the overlay also opens its settings menu.
4. Play music or change volume/brightness to see an enabled activity.
5. Press and hold a supported activity to expand it. Gestures are configurable.

Closing a window keeps Notch running. Use the menu-bar **Quit** command to stop it.
Use **Welcome & Help…** to reopen the introduction.

### A fresh identity

The visible app name is **Notch**, the publisher is **infynite**, and internal
product names are lowercase `notch`.

- Bundle ID: `in.infynite.notch`
- Project/module/scheme: `notch`
- Executable: `Notch.app/Contents/MacOS/notch`
- Interface: English only, regardless of macOS language
- Preferences: a fresh domain; old settings and credentials are not imported

Notch detects running legacy copies and asks to quit them. It never deletes their
settings. See [NOTICE.md](NOTICE.md) for upstream attribution.

## Coding-agent companion

Open **AI Agents…** from the menu bar, then choose **Connect** for OpenCode V2,
Codex, or Claude Code. Node.js 18+ is required. Setup uses a stable adapter folder
under `~/Library/Application Support/in.infynite.notch/agents`.

- OpenCode: the plugin loads through global configuration; `/reload` if needed.
- Codex: review and trust hooks in `/hooks` or **Settings → Hooks**.
- Claude Code: review hooks, then start a new session.

**Verify** tests the local receiver; **Real activity received** confirms a real
provider event. These are deliberately separate. Send a prompt to complete setup.
Disconnect removes only Notch's registrations and preserves unrelated settings.
Existing edited configuration is backed up alongside the original.

Working status yields to music. Attention requests take priority. No chat text,
API keys, source code, or approval decisions travel to Notch. Remote/cloud agent
sessions cannot access the local socket. See the
[integration guide](notch/Resources/AIAgentIntegrations/README-AI-AGENTS.md).

## Build and test

Use Xcode 26+ with a current macOS SDK. The app targets macOS 14.6+; native adaptive
icon appearances require macOS 26+. Dependencies resolve through SwiftPM.

```sh
open notch.xcodeproj
node --test tests/ai-agents/bridge.test.mjs
python3 scripts/check-branding.py
xcodebuild -project notch.xcodeproj -scheme notch \
  -destination 'platform=macOS' CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

Build without touching Applications:

```sh
INSTALL_APP=NO bash build_and_install_app.sh
```

The default build is ad-hoc signed, **not Apple-notarized**.
All distributable outputs use the same repo-local `build/` directory:
`build/Notch.app`, `build/notch-installer.pkg`, `build/notch.dmg`, and
`build/notch.zip`. Xcode caches stay underneath `build/notch-derived/`.

## Installers

```sh
bash build_pkg.sh
INSTALLER_PATH="$PWD/build/notch-installer.pkg" bash build_dmg.sh
```

Open `build/notch.dmg` and run **Install Notch.pkg**. macOS Installer requests
administrator approval when replacing a root-owned installation. Quit old copies
first. The direct-install script stages a complete app before replacement and
will not partially delete an installation when permissions are insufficient.

## Updates and releases

Sparkle checks **only** the Notch release feed:
`https://github.com/infynitehq/notch/releases/latest/download/appcast.xml`.
Automatic checks/downloads are opt-in under **Settings → About → Software Update**.
Updates must match the new Notch Ed25519 public key; upstream updates cannot
replace this fork.

See [releasing](docs/releasing.md) for signing, draft releases, and the remaining
Apple Developer/notarization prerequisites. Nothing is published by a local build.

## Contribute

[Issues](https://github.com/infynitehq/notch/issues) ·
[Contributing](CONTRIBUTING.md) · [infynite](https://infynite.in)

GNU GPL v3. See [LICENSE](LICENSE) and [NOTICE.md](NOTICE.md).
