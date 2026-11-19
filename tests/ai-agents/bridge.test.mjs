import test from "node:test";
import assert from "node:assert/strict";
import net from "node:net";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import {
  makeEvent, normalizeHook, sendEvent, mergeHooks, hookConfiguration, originFromEnvironment,
} from "../../notch/Resources/AIAgentIntegrations/bridge.mjs";
import { normalizeOpenCodeEvent } from "../../notch/Resources/AIAgentIntegrations/opencode-events.mjs";
import { startCompanion } from "../../notch/Resources/AIAgentIntegrations/opencode-runtime.mjs";
import { parseJSONC, updatePlugins } from "../../notch/Resources/AIAgentIntegrations/opencode-config.mjs";

const script = fileURLToPath(new URL("../../notch/Resources/AIAgentIntegrations/bridge.mjs", import.meta.url));

test("Claude/Codex lifecycle fixtures map without leaking sensitive payloads", () => {
  const mappings = {
    SessionStart: "idle", UserPromptSubmit: "started", PreToolUse: "activity",
    PermissionRequest: "attention", PostToolUse: "activity", Stop: "completed",
    StopFailure: "failed", SessionEnd: "ended", Interrupt: "ended",
  };
  for (const provider of ["claude", "codex"]) {
    for (const [hook_event_name, kind] of Object.entries(mappings)) {
      const event = normalizeHook(provider, {
        hook_event_name, session_id: "session-1", cwd: "/private/company/project",
        prompt: "TOP_SECRET", tool_input: { command: "TOP_SECRET" },
        last_assistant_message: "TOP_SECRET", transcript_path: "/secret",
      });
      assert.equal(event.kind, kind);
      assert.equal(event.project, "project");
      assert.ok(!JSON.stringify(event).includes("TOP_SECRET"));
      assert.ok(!JSON.stringify(event).includes("/private"));
      assert.ok(!JSON.stringify(event).includes("transcript"));
    }
  }
});

test("ignore subagents, malformed IDs and irrelevant notifications", () => {
  assert.equal(normalizeHook("claude", { session_id: "one", hook_event_name: "Stop", agent_id: "child" }), undefined);
  assert.equal(normalizeHook("codex", { hook_event_name: "Stop" }), undefined);
  assert.equal(makeEvent("codex", "../bad", "started"), undefined);
  assert.equal(makeEvent("bad", "one", "started"), undefined);
  assert.equal(normalizeHook("claude", { session_id: "one", hook_event_name: "Notification", notification_type: "auth_success" }), undefined);
  assert.equal(normalizeHook("claude", { session_id: "one", hook_event_name: "Notification", notification_type: "permission_prompt" }).kind, "attention");
});

test("named Claude main sessions are not mistaken for subagents", () => {
  const input = { session_id: "main", hook_event_name: "UserPromptSubmit", agent_type: "reviewer" };
  assert.equal(normalizeHook("claude", input).kind, "started");
  assert.equal(normalizeHook("claude", { ...input, agent_id: "child" }), undefined);
});

test("OpenCode JSONC changes preserve unrelated settings, strings, and comments", () => {
  const source = `{
    // Keep this comment.
    "providers": { "example": { "url": "https://host/path//not-comment", }, },
    "plugins": ["other", { "package": "another", "options": { "enabled": true } },],
    "model": "openai/example",
  }`;
  const plugin = "/Application Support/notch/agents";
  const once = updatePlugins(source, plugin);
  assert.ok(once.includes("// Keep this comment."));
  assert.deepEqual(parseJSONC(once).data.plugins, [
    "other", { package: "another", options: { enabled: true } }, plugin,
  ]);
  assert.equal(parseJSONC(once).data.providers.example.url, "https://host/path//not-comment");
  assert.equal(updatePlugins(once, plugin), once);
  const removed = updatePlugins(once, plugin, true);
  assert.deepEqual(parseJSONC(removed).data, parseJSONC(source).data);
});

test("OpenCode JSONC insertion supports empty config, nested plugins, and trailing commas", () => {
  for (const source of ['{}', '{ /* keep */ }', '{"model":"m",}', '{"options":{"plugins":[]}}']) {
    const result = updatePlugins(source, "/notch");
    assert.deepEqual(parseJSONC(result).data.plugins, ["/notch"]);
    assert.deepEqual(parseJSONC(updatePlugins(result, "/notch", true)).data.plugins, []);
  }
  assert.throws(() => updatePlugins('{"plugins":{}}', "/notch"));
  assert.throws(() => updatePlugins('{ /* never closed', "/notch"));
});

test("OpenCode install/disconnect backs up JSONC without touching other plugins", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "notch-opencode-"));
  const configDir = path.join(directory, "opencode");
  fs.mkdirSync(configDir);
  const file = path.join(configDir, "opencode.jsonc");
  fs.writeFileSync(file, '{ // preserve me\\n "plugins":["other"], "model":"mine", }'.replace("\\n", "\n"));
  const env = { ...process.env, OPENCODE_CONFIG_DIR: configDir };
  delete env.OPENCODE_CONFIG;
  try {
    const install = spawnSync(process.execPath, [script, "install", "opencode"], { env });
    assert.equal(install.status, 0, install.stderr.toString());
    const data = parseJSONC(fs.readFileSync(file, "utf8")).data;
    assert.equal(data.model, "mine");
    assert.equal(data.plugins.length, 2);
    assert.equal(spawnSync(process.execPath, [script, "uninstall", "opencode"], { env }).status, 0);
    assert.deepEqual(parseJSONC(fs.readFileSync(file, "utf8")).data.plugins, ["other"]);
    assert.ok(fs.readdirSync(configDir).some(name => name.endsWith(".bak")));
  } finally { fs.rmSync(directory, { recursive: true }); }
});

test("event timestamps are strictly ordered inside a plugin process", () => {
  let previous = 0;
  for (let i = 0; i < 100; i++) {
    const event = makeEvent("opencode", "ses-one", "activity");
    assert.ok(event.timestamp > previous);
    previous = event.timestamp;
  }
});

test("origin metadata uses only known bundle IDs", () => {
  assert.equal(originFromEnvironment({ TERM_PROGRAM: "ghostty" }), "com.mitchellh.ghostty");
  assert.equal(originFromEnvironment({ __CFBundleIdentifier: "evil.command" }), undefined);
  assert.equal(originFromEnvironment({ TERM_PROGRAM: "unknown" }), undefined);
});

test("hook installation is idempotent and uninstall preserves other settings", () => {
  const original = {
    permissions: { allow: ["Bash(git *)"] },
    hooks: { Stop: [{ matcher: "anything", hooks: [{ type: "command", command: "my-hook" }] }] },
  };
  for (const provider of ["claude", "codex"]) {
    const once = mergeHooks(original, provider);
    const twice = mergeHooks(once, provider);
    assert.deepEqual(once, twice);
    assert.deepEqual(mergeHooks(twice, provider, true), original);
    assert.equal(original.hooks.Stop.length, 1);
    assert.equal(once.hooks.Stop[1].hooks[0].timeout, 1);
    assert.equal(once.hooks.PermissionRequest[0].hooks[0].async, undefined);
  }
});

test("uninstall does not remove another integration using a script named bridge.mjs", () => {
  const original = { hooks: { Stop: [{ hooks: [{ type: "command", command: "'node' '/another/bridge.mjs' hook claude" }] }] } };
  assert.deepEqual(mergeHooks(original, "claude", true), original);
});

test("uninstall preserves unrelated empty matcher groups", () => {
  const original = { hooks: { Stop: [{ matcher: "user-choice", hooks: [] }] } };
  assert.deepEqual(mergeHooks(mergeHooks(original, "claude"), "claude", true), original);
});

test("installer refuses broken configuration symlinks without replacing them", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "dna-symlink-"));
  const file = path.join(directory, "settings.json");
  fs.symlinkSync(path.join(directory, "missing.json"), file);
  try {
    const result = spawnSync(process.execPath, [script, "install", "claude"], {
      env: { ...process.env, CLAUDE_CONFIG_DIR: directory },
    });
    assert.equal(result.status, 1);
    assert.ok(fs.lstatSync(file).isSymbolicLink());
  } finally { fs.rmSync(directory, { recursive: true }); }
});

test("installer rejects unexpected configuration rather than overwriting it", () => {
  for (const input of [[], null, { hooks: [] }, { hooks: { Stop: {} } }, { hooks: { Stop: [{}] } }]) {
    assert.throws(() => mergeHooks(input, "claude"));
  }
});

test("generated hooks safely quote executable and kit paths", () => {
  const hooks = hookConfiguration("codex", "/my folder/it's/bridge.mjs", "/node folder/node");
  const command = hooks.Stop[0].hooks[0].command;
  assert.ok(command.includes("'/node folder/node'"));
  assert.ok(command.includes("it'\\''s"));
});

test("real Unix socket receives one bounded metadata line", async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "dna-"));
  const socket = path.join(directory, "e.sock");
  let resolveMessage;
  const message = new Promise((resolve) => { resolveMessage = resolve; });
  const server = net.createServer((connection) => {
    let body = "";
    connection.on("data", (chunk) => { body += chunk; });
    connection.on("end", () => { resolveMessage(body); connection.end(); });
  });
  try {
    await new Promise((resolve) => server.listen(socket, resolve));
    const event = makeEvent("codex", "session-one", "started");
    assert.equal(await sendEvent(event, socket), true);
    const body = await message;
    assert.ok(body.endsWith("\n"));
    assert.deepEqual(JSON.parse(body), JSON.parse(JSON.stringify(event)));
  } finally {
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(directory, { recursive: true });
  }
});

test("unavailable companion fails open promptly", async () => {
  const before = Date.now();
  assert.equal(await sendEvent(makeEvent("codex", "one", "started"), "/nonexistent/notch.sock"), false);
  assert.ok(Date.now() - before < 1000);
});

test("real install/uninstall backs up and preserves a user's configuration", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "dna-config-"));
  const file = path.join(directory, "settings.json");
  const original = { model: "user-model", hooks: { Stop: [{ hooks: [{ type: "command", command: "other" }] }] } };
  fs.writeFileSync(file, JSON.stringify(original));
  const env = { ...process.env, CLAUDE_CONFIG_DIR: directory };
  try {
    assert.equal(spawnSync(process.execPath, [script, "install", "claude"], { env }).status, 0);
    assert.equal(spawnSync(process.execPath, [script, "install", "claude"], { env }).status, 0);
    assert.equal(JSON.parse(fs.readFileSync(file)).hooks.Stop.length, 2);
    assert.ok(fs.readdirSync(directory).some((name) => name.endsWith(".bak")));
    assert.equal(spawnSync(process.execPath, [script, "uninstall", "claude"], { env }).status, 0);
    assert.deepEqual(JSON.parse(fs.readFileSync(file)), original);
  } finally { fs.rmSync(directory, { recursive: true }); }
});

test("command hook stays silent and successful for invalid input and closed app", () => {
  for (const input of ["bad json", JSON.stringify({ session_id: "one", hook_event_name: "Stop", prompt: "secret" })]) {
    const result = spawnSync(process.execPath, [script, "hook", "codex"], { input, timeout: 2000 });
    assert.equal(result.status, 0);
    assert.equal(result.stdout.toString(), "");
    assert.equal(result.stderr.toString(), "");
  }
});

test("OpenCode V2 execution, permission and form fixtures", () => {
  for (const [type, kind] of [
    ["session.execution.started", "started"], ["session.execution.succeeded", "completed"],
    ["session.execution.failed", "failed"], ["session.execution.interrupted", "ended"],
    ["permission.asked", "attention"], ["permission.replied", "activity"],
  ]) {
    const mapped = normalizeOpenCodeEvent({ type, data: { sessionID: "ses-one", id: "req", input: "SECRET" } });
    assert.equal(mapped.kind, kind);
    assert.equal(mapped.sessionID, "ses-one");
    assert.ok(!JSON.stringify(mapped).includes("SECRET"));
  }
  assert.equal(normalizeOpenCodeEvent({ type: "form.created", data: { form: { id: "f1", sessionID: "ses-one" } } }).kind, "attention");
  assert.equal(normalizeOpenCodeEvent({ type: "session.text.ended", data: { sessionID: "ses-one" } }), undefined);
});

function fakeContext(events, fail = false) {
  return {
    event: { async *subscribe({ signal }) {
      for (const event of events) yield event;
      if (fail) throw Error("stream disconnected");
      await new Promise((resolve) => {
        if (signal.aborted) resolve();
        else signal.addEventListener("abort", resolve, { once: true });
      });
    } },
    session: { async get() { throw Error("metadata unavailable"); } },
  };
}

test("OpenCode runtime retains attention until all concurrent permission/form requests resolve", async () => {
  const fixture = (type, data = {}) => ({
    id: `event-${Math.random().toString().slice(2)}`, type,
    location: { directory: "/project/alpha" },
    data: { sessionID: "ses-one", ...data },
  });
  const fixtures = [
    fixture("session.execution.started"),
    fixture("permission.asked", { id: "p1" }),
    fixture("form.created", { form: { id: "f1", sessionID: "ses-one" } }),
    fixture("permission.replied", { requestID: "p1" }),
    fixture("session.tool.called"),
    fixture("form.replied", { id: "f1" }),
    fixture("session.execution.succeeded"),
  ];
  const sent = [];
  let done;
  const received = new Promise((resolve) => { done = resolve; });
  const cleanup = startCompanion(fakeContext(fixtures), { send: async (event) => {
    sent.push(event);
    if (sent.length === fixtures.length) done();
  } });
  try {
    await received;
    assert.deepEqual(sent.map((event) => event.kind),
      ["started", "attention", "attention", "attention", "attention", "activity", "completed"]);
    assert.equal(sent[0].eventID, fixtures[0].id);
    assert.equal(sent[0].project, "alpha");
  } finally { await cleanup(); }
  assert.equal(sent.length, fixtures.length);
});

test("OpenCode stream failure ends active sessions rather than renewing false liveness", async () => {
  const sent = [];
  let done;
  const disconnected = new Promise((resolve) => { done = resolve; });
  const cleanup = startCompanion(fakeContext([{
    type: "session.execution.started", data: { sessionID: "ses-one" },
  }], true), { send: async (event) => {
    sent.push(event);
    if (event.kind === "ended") done();
  } });
  try {
    await disconnected;
    assert.deepEqual(sent.map((event) => event.kind), ["started", "ended"]);
    assert.equal(sent[0].project, undefined);
  } finally { await cleanup(); }
});
