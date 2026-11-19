# Releasing Notch

## Current trust model

Notch has its own bundle ID (`in.infynite.notch`), update feed, and Ed25519
update-signing key. The private key was generated in the macOS login Keychain
under Sparkle account **`in.infynite.notch`**. It is not stored in this repository.
Only its public key is bundled in the app.

**Do not rotate the public key casually:** existing installations must be able
to authenticate the next update.

Without Apple Developer membership, builds are ad-hoc signed and not notarized.
Sparkle signing authenticates updates but does not give Gatekeeper trust.
Do not describe these builds as Apple-signed or notarized.

## Local release preparation

1. Increment `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in both app build
   configurations. Build numbers must strictly increase.
2. Run the Node tests, branding check, and macOS test suite.
3. Build Release from a clean derived-data path, universal arm64/x86_64 for
   public releases. Check `lipo -archs` and `codesign --verify --deep --strict`.
4. Package an update:

```sh
ditto -c -k --sequesterRsrc --keepParent build/Notch.app build/notch.zip
```

5. Find Sparkle's `bin/sign_update` in the resolved SwiftPM artifacts, then:

```sh
signature="$("$SPARKLE_BIN/sign_update" --account in.infynite.notch -p build/notch.zip)"
node scripts/make-appcast.mjs build/Notch.app build/notch.zip "$signature" build/appcast.xml
bash build_pkg.sh
INSTALLER_PATH="$PWD/build/notch-installer.pkg" OUTPUT_DIR="$PWD/build" bash build_dmg.sh
```

Feed generation verifies the archive signature against the actual built app's
public key. A wrong CI signing key fails rather than shipping an unusable update.

## GitHub draft workflow

The manual **Prepare signed Notch update** workflow builds universal binaries,
packages installers, signs the update ZIP, verifies the signature, and creates
a **draft** release. It does not publish automatically.

Configure `SPARKLE_PRIVATE_KEY` as a GitHub Actions secret yourself. Use Sparkle's
`generate_keys --account in.infynite.notch -x <private-file>` to export your own
key when ready; protect that file and never add it to Git. The workflow passes
the secret through stdin, not command-line arguments or logs.

Each release must include `notch.zip`, `notch.dmg`, `notch-installer.pkg`, and
`appcast.xml`. Once you publish the draft as the latest release, this stable
feed resolves to its signed update:

`https://github.com/infynitehq/notch/releases/latest/download/appcast.xml`

The root `appcast.xml` is an empty template, not a copy of upstream releases.
Do not publish an empty placeholder as the release feed.

## Before publishing

- Test fresh installation and replacement of an administrator-owned app.
- Confirm launch prompts for old running copies without deleting their data.
- Verify English-only interface, adaptive icon and lowercase internal identity.
- Connect and disconnect all three agents, checking real provider events and
  permission/trust steps. Synthetic Verify events are not proof of agent wiring.
- Test a real version-to-version Sparkle update on a test Mac, including signature
  rejection and preserved Notch preferences.
- Publish the GPL source corresponding to the binaries and preserve NOTICE.md.

## Later: Developer ID and notarization

When infynite has Apple Developer membership, add Developer ID certificate
management, hardened-runtime signing of the app and nested components,
`notarytool` submission, stapling, and installer signing to the release workflow.
Do not enable hardened runtime indiscriminately before validating existing
private-framework features and entitlements. Signing identities are supplied
by the release environment, never hardcoded to the original developer's team.
