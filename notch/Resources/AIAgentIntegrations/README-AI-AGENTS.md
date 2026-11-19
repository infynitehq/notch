# Notch agent companion

Use **Notch menu bar → AI Agents… → Connect**. Node.js 18+ is required.
The app installs these adapters in a stable application-support directory.
Connections require local agent execution on the same Mac and user account.

## Providers

- **OpenCode V2:** Connect adds this package to the global `plugins` array in
  `~/.config/opencode/opencode.json(c)`. JSONC comments and unrelated settings
  are preserved. Both global config formats at once require manual resolution.
  OpenCode watches configuration; use `/reload` if necessary.
- **Codex:** Connect merges lifecycle hooks into `$CODEX_HOME/hooks.json`
  (default `~/.codex/hooks.json`). Review and trust them through `/hooks` or
  desktop **Settings → Hooks**. Policy can restrict hooks; Notch never bypasses it.
- **Claude Code:** Connect merges lifecycle hooks into
  `$CLAUDE_CONFIG_DIR/settings.json` (default `~/.claude/settings.json`).
  Review them, then start a new session. Named main agents are supported;
  subagent callbacks do not mutate the parent status.

Agent detection is advisory. Desktop apps may not expose their CLI in PATH.
You can connect an agent even if it isn't detected. Choose Node.js manually
when a version manager's executable cannot be discovered.

## Verify the complete connection

1. Enable the companion. The receiver must say **Listening locally**.
2. Connect the agent and complete any review/trust step.
3. **Verify** sends a synthetic completion event. **Local test received**
   proves only that the receiver accepted it.
4. Submit a real prompt in your agent. **Real activity received** confirms
   real provider events. Check working, attention, and finished states.

Working yields to media. Attention takes priority over ordinary live activities.
Completions display for eight seconds. Closing Notch drops events; there is no
disk queue or historical scan. Sessions are in-memory only.

## Manual setup

Keep this package at a permanent path:

```sh
node bridge.mjs install opencode
node bridge.mjs install codex
node bridge.mjs install claude
node bridge.mjs doctor
node bridge.mjs test opencode
```

Use `uninstall` instead of `install` to disconnect. Existing configurations get
backups alongside them. Installers refuse symlinks, malformed configuration, and
unexpected shapes rather than overwriting them. Only Notch's registrations are
removed. No files from an old product identity are automatically migrated.

## Privacy and protocol

The receiver uses `~/.notch/events.sock` in a private 0700 directory, with a 0600
socket and same-user peer verification. It opens no TCP listener and rejects
unexpected fields, malformed IDs, stale timestamps, unsafe paths, and oversized
payloads. Other processes running as you can spoof metadata; this is a status
display, not an approval or audit boundary.

Only provider/session IDs, event IDs/types/timestamps, optional project basename,
and a known origin app are forwarded. No prompts, transcripts, tool arguments,
source code, API keys, or responses are collected. Activity is hidden while locked.
Hooks remain silent and never approve or deny an action.

Command hooks time out quickly. OpenCode active sessions emit 30-second
heartbeats. Fifteen minutes of silence makes status unknown, not failed.
“Finished” means a response ended, not that tests passed.

One JSON object plus newline per connection, maximum 4096 bytes:

```json
{"version":1,"eventID":"event-1","provider":"opencode","sessionID":"session-1","kind":"started","timestamp":1795000000000}
```

Providers: `claude`, `codex`, `opencode`. Kinds: `idle`, `started`, `activity`,
`attention`, `completed`, `failed`, `ended`, `heartbeat`. Optional: `project`,
`origin`. Timestamps are Unix milliseconds within two minutes of receiver time.

References:
- https://opencode.ai/docs/build/plugins/server
- https://developers.openai.com/codex/hooks
- https://code.claude.com/docs/en/hooks
