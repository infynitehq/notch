# Contributing to Notch

Notch is maintained by infynite. Please open issues and pull requests at
https://github.com/infynitehq/notch.

## Development

Use Xcode 26+ and a current macOS SDK:

```sh
git clone https://github.com/infynitehq/notch.git
cd notch
open notch.xcodeproj
```

Select the `notch` scheme. Local builds use ad-hoc signing; no upstream developer
team or credentials are required.

- `notch/Application`: lifecycle, windows, composition
- `notch/Core`: settings, notch engine, utilities
- `notch/Features`: feature-owned services, models, views
- `notch/Resources`: English strings, assets, agent adapters
- `notchtests`: unit and integration tests
- `notchuitests`: UI tests
- `tests/ai-agents`: Node.js adapter tests

## Naming and design

Visible product name: **Notch**. Publisher: **infynite**.
Product identifiers, package names, module names and filesystem namespaces use
lowercase `notch`. Swift types otherwise follow standard Swift conventions.

The interface is English-only. Keep user-facing strings in the English catalog
or use explicit readable text; do not add language pickers or flags.
Preserve the native macOS feel, monochrome brand, keyboard accessibility, and
reduced-motion support. Functional status colors can remain semantic.

## Verification

```sh
node --test tests/ai-agents/bridge.test.mjs
python3 scripts/check-branding.py
xcodebuild -project notch.xcodeproj -scheme notch -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= test
```

Add regression tests for bug fixes. Agent adapter tests must use temporary
configurations and never modify the developer's live agent settings. Mock tests
do not replace real provider verification before release.

Never commit credentials, private signing keys, build outputs, or personal paths.
Keep upstream copyright notices and attribution intact. Contributions remain
under GNU GPL v3; see LICENSE and NOTICE.md.
