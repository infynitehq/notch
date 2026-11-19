# Security

For a suspected vulnerability, use private vulnerability reporting on
https://github.com/infynitehq/notch/security/advisories/new when available.
If private reporting is unavailable, open an issue asking for a private contact
without posting exploit details or secrets.

Notch's agent companion is a local awareness display, not an approval mechanism.
Events from processes running as the same macOS user can be spoofed.
Never use its status as proof that code, tests, or a command is safe.

Public updates must be signed with the Notch Ed25519 key. Release archives are
verified against the public key embedded in the app before feed generation.
Apple Developer ID signing and notarization are separate prerequisites for
Gatekeeper-trusted distribution. Local builds are not notarized.

Please redact API keys, prompts, transcripts, source code, and identifying paths
when sharing logs. See NOTICE.md for upstream attribution.
