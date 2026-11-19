import net from "node:net";
import os from "node:os";
import path from "node:path";
import fs from "node:fs";
import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { configureOpenCode, openCodeConfigPath, parseJSONC } from "./opencode-config.mjs";

export const socketPath = path.join(os.homedir(), ".notch", "events.sock");
const providers = new Set(["claude", "codex", "opencode"]);
const identifier = /^[\p{L}\p{N}_.:-]{1,200}$/u;
const allowedOrigins = new Set([
  "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
  "dev.warp.Warp-Stable", "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92",
  "ai.opencode.desktop", "com.anthropic.claudefordesktop", "com.openai.codex",
]);
export function originFromEnvironment(env = process.env) {
  if (allowedOrigins.has(env.__CFBundleIdentifier)) return env.__CFBundleIdentifier;
  return ({
    Apple_Terminal: "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2",
    ghostty: "com.mitchellh.ghostty", WarpTerminal: "dev.warp.Warp-Stable",
    vscode: "com.microsoft.VSCode",
  })[env.TERM_PROGRAM];
}

let lastTimestamp = 0;
export function makeEvent(provider, sessionID, kind, metadata = {}) {
  if (!providers.has(provider) || typeof sessionID !== "string" || !identifier.test(sessionID)) return;
  // Preserve ordering even when several callbacks occur in one millisecond.
  lastTimestamp = Math.max(Date.now(), lastTimestamp + 0.001);
  return {
    version: 1, eventID: typeof metadata.eventID === "string" && identifier.test(metadata.eventID)
      ? metadata.eventID : randomUUID(), provider, sessionID, kind,
    timestamp: metadata.timestamp ?? lastTimestamp,
    project: typeof metadata.directory === "string" ? path.basename(metadata.directory).slice(0, 80) : undefined,
    origin: originFromEnvironment(),
  };
}

/** Fail-open and quiet. Never retry or queue events when the companion is unavailable. */
export function sendEvent(event, destination = socketPath) {
  if (!event) return Promise.resolve(false);
  const line = JSON.stringify(event) + "\n";
  if (Buffer.byteLength(line) > 4096) return Promise.resolve(false);
  return new Promise((resolve) => {
    let settled = false;
    const socket = net.createConnection({ path: destination });
    const finish = (ok) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      socket.destroy();
      resolve(ok);
    };
    const timer = setTimeout(() => finish(false), 250);
    socket.on("error", () => finish(false));
    socket.on("connect", () => socket.end(line, () => finish(true)));
  });
}

export function normalizeHook(provider, input, timestamp = Date.now()) {
  if (!["claude", "codex"].includes(provider) || !input || typeof input !== "object") return;
  // Subagent tool callbacks must not mutate the parent session's status.
  if (input.agent_id) return;
  let kind = ({
    SessionStart: "idle", UserPromptSubmit: "started",
    PreToolUse: "activity", PostToolUse: "activity", PostToolUseFailure: "activity",
    PermissionRequest: "attention", Stop: "completed", StopFailure: "failed",
    SessionEnd: "ended", Interrupt: "ended",
  })[input.hook_event_name];
  if (input.hook_event_name === "Notification") {
    if (["permission_prompt", "elicitation_dialog", "agent_needs_input", "idle_prompt"].includes(input.notification_type)) {
      kind = "attention";
    } else return;
  }
  if (!kind) return;
  return makeEvent(provider, input.session_id, kind, { directory: input.cwd, timestamp });
}

function shellQuote(value) { return "'" + value.replaceAll("'", "'\\''") + "'"; }
export function hookConfiguration(provider, script = fileURLToPath(import.meta.url), node = process.execPath) {
  if (!["claude", "codex"].includes(provider)) throw Error("Choose claude or codex");
  const events = [
    "SessionStart", "UserPromptSubmit", "PreToolUse", "PermissionRequest",
    "PostToolUse", "Stop", "SessionEnd",
    ...(provider === "claude" ? ["StopFailure", "PostToolUseFailure", "Notification"] : ["Interrupt"]),
  ];
  const command = `${shellQuote(node)} ${shellQuote(script)} hook ${provider} --notch-agent-hook-v1`;
  return Object.fromEntries(events.map((event) => [event, [{
    ...(event === "Notification" ? { matcher: "permission_prompt|elicitation_dialog|agent_needs_input|idle_prompt" } : {}),
    // Keep command hooks synchronous and short to preserve lifecycle order.
    // No stdout decisions; permissions remain entirely in the agent.
    hooks: [{ type: "command", command, timeout: 1 }],
  }]]));
}

function ours(handler) {
  return handler?.type === "command" && typeof handler.command === "string" &&
    handler.command.endsWith(" --notch-agent-hook-v1") &&
    handler.command.includes("bridge.mjs' hook ");
}
export function mergeHooks(config, provider, uninstall = false, script, node) {
  if (!config || typeof config !== "object" || Array.isArray(config)) throw Error("Settings must be a JSON object");
  const result = structuredClone(config);
  if (result.hooks != null && (typeof result.hooks !== "object" || Array.isArray(result.hooks))) {
    throw Error("Existing hooks must be an object; nothing changed");
  }
  result.hooks ??= {};
  const additions = hookConfiguration(provider, script, node);
  for (const event of Object.keys(additions)) {
    const groups = result.hooks[event] ?? [];
    if (!Array.isArray(groups)) throw Error(`Existing ${event} hooks must be an array; nothing changed`);
    result.hooks[event] = groups.flatMap((group) => {
      if (!Array.isArray(group.hooks)) throw Error("Unrecognized hook configuration; nothing changed");
      const handlers = group.hooks.filter((handler) => !ours(handler));
      // Preserve unrelated empty groups too; remove only groups emptied by our uninstall.
      return !handlers.length && group.hooks.some(ours) ? [] : [{ ...group, hooks: handlers }];
    });
    if (!uninstall) result.hooks[event].push(...additions[event]);
    if (!result.hooks[event].length) delete result.hooks[event];
  }
  return result;
}

function configure(provider, uninstall) {
  const file = provider === "claude"
    ? path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), ".claude"), "settings.json")
    : path.join(process.env.CODEX_HOME || path.join(os.homedir(), ".codex"), "hooks.json");
  // Refuse symlinked configuration rather than accidentally modifying its target.
  let info;
  try { info = fs.lstatSync(file); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  const exists = info !== undefined;
  if (exists && !info.isFile()) throw Error("Configuration is not a regular file");
  const previous = exists ? fs.readFileSync(file, "utf8") : "{}";
  const result = mergeHooks(JSON.parse(previous), provider, uninstall);
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  if (exists) fs.copyFileSync(file, `${file}.notch-${Date.now()}-${randomUUID()}.bak`, fs.constants.COPYFILE_EXCL);
  const temporary = `${file}.notch-${randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temporary, JSON.stringify(result, null, 2) + "\n", { flag: "wx", mode: 0o600 });
    // Detect a concurrent edit before replacing the settings.
    if ((exists && fs.readFileSync(file, "utf8") !== previous) || (!exists && fs.existsSync(file))) {
      throw Error("Settings changed concurrently; retry");
    }
    fs.renameSync(temporary, file);
  } finally {
    if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
  }
  console.log(`${uninstall ? "Removed" : "Installed"} notch hooks in ${file}. Existing settings preserved.`);
  if (!uninstall) console.log("Review/trust the new hooks in your agent. Keep this integration kit at its current path.");
}

async function main() {
  const [command, provider] = process.argv.slice(2);
  if (command === "hook") {
    // Record observation time before reading input. Provider stdin may contain secrets;
    // only normalizeHook's explicit metadata allowlist ever leaves this process.
    const timestamp = performance.timeOrigin + performance.now();
    const deadline = setTimeout(() => process.exit(0), 750);
    let size = 0;
    const chunks = [];
    for await (const chunk of process.stdin) {
      size += chunk.length;
      if (size > 1024 * 1024) { clearTimeout(deadline); return; }
      chunks.push(chunk);
    }
    try { await sendEvent(normalizeHook(provider, JSON.parse(Buffer.concat(chunks).toString()), timestamp)); }
    catch { /* Observability must never break the coding agent. */ }
    finally { clearTimeout(deadline); }
  } else if (["install", "uninstall"].includes(command) && providers.has(provider)) {
    if (provider === "opencode") {
      const file = configureOpenCode(path.dirname(fileURLToPath(import.meta.url)), command === "uninstall");
      console.log(`Notch plugin ${command === "uninstall" ? "removed from" : "added to"} ${file}. Use /reload in OpenCode if needed.`);
    } else configure(provider, command === "uninstall");
  } else if (command === "doctor") {
    const installed = {};
    for (const name of ["claude", "codex"]) {
      const file = name === "claude"
        ? path.join(process.env.CLAUDE_CONFIG_DIR || path.join(os.homedir(), ".claude"), "settings.json")
        : path.join(process.env.CODEX_HOME || path.join(os.homedir(), ".codex"), "hooks.json");
      try {
        const config = JSON.parse(fs.readFileSync(file, "utf8"));
        const groups = Object.values(config.hooks ?? {}).flat();
        installed[name] = groups.some(group => group.hooks?.some(ours));
      } catch { installed[name] = false; }
    }
    try {
      const config = parseJSONC(fs.readFileSync(openCodeConfigPath(), "utf8")).data;
      const directory = path.dirname(fileURLToPath(import.meta.url));
      installed.opencode = config.plugins?.some(value => value === directory || value?.package === directory) ?? false;
    } catch { installed.opencode = false; }
    console.log(JSON.stringify({ node: process.version, installed }));
  } else if (command === "test") {
    const ok = await sendEvent(makeEvent(providers.has(provider) ? provider : "codex",
      `test-${randomUUID()}`, "completed", { directory: "Connection test" }));
    console.log(ok ? "Test sent. Waiting for receiver confirmation in Notch." : "Bridge unavailable. Enable AI Agents in Notch first.");
    process.exitCode = ok ? 0 : 1;
  } else {
    throw Error("Usage: node bridge.mjs install|uninstall claude|codex|opencode, doctor, or test [provider]");
  }
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    if (process.argv[2] !== "hook") { console.error(error.message); process.exitCode = 1; }
  });
}
