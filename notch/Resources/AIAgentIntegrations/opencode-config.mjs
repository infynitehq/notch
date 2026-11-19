import fs from "node:fs";
import path from "node:path";
import os from "node:os";
import { randomUUID } from "node:crypto";

// Preserve comments and unrelated settings when changing only the plugins property.
export function parseJSONC(text) {
  let clean = "", string = false, escape = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i], next = text[i + 1];
    if (string) {
      clean += c;
      if (escape) escape = false;
      else if (c === "\\") escape = true;
      else if (c === '"') string = false;
    } else if (c === '"') { string = true; clean += c; }
    else if (c === "/" && next === "/") {
      clean += "  "; i++;
      while (i + 1 < text.length && text[i + 1] !== "\n") { clean += " "; i++; }
    } else if (c === "/" && next === "*") {
      clean += "  "; i++;
      while (i + 1 < text.length && !(text[i] === "*" && text[i + 1] === "/")) {
        i++; clean += text[i] === "\n" ? "\n" : " ";
      }
      if (i + 1 >= text.length) throw Error("Unclosed configuration comment");
      i++; clean += " ";
    } else clean += c;
  }
  // Remove trailing commas without altering string contents or offsets.
  clean = clean.replace(/"(?:\\.|[^"\\])*"|,(\s*[}\]])/g, (match, trailing) =>
    trailing ? " " + trailing : match);
  const data = JSON.parse(clean);
  if (!data || Array.isArray(data) || typeof data !== "object") throw Error("Configuration must be an object");
  return { data, clean };
}

export function updatePlugins(text, pluginPath, uninstall = false) {
  const { data, clean } = parseJSONC(text);
  if (data.plugins !== undefined && !Array.isArray(data.plugins)) throw Error("Existing plugins must be an array");
  const ours = value => value === pluginPath || value?.package === pluginPath;
  const plugins = (data.plugins ?? []).filter(value => !ours(value));
  if (!uninstall) plugins.push(pluginPath);
  if (JSON.stringify(plugins) === JSON.stringify(data.plugins ?? []) && (uninstall || data.plugins)) return text;
  // Locate the root plugins property, ignoring strings and nested properties.
  let depth = 0;
  const tokens = /"(?:\\.|[^"\\])*"|[{}[\]]/g;
  for (const token of clean.matchAll(tokens)) {
    const t = token[0];
    if (t.startsWith('"')) {
      if (depth !== 1 || JSON.parse(t) !== "plugins") continue;
      const after = clean.slice(token.index + t.length);
      const prefix = after.match(/^\s*:\s*/);
      if (!prefix) continue;
      const start = token.index + t.length + prefix[0].length;
      if (clean[start] !== "[") throw Error("Existing plugins must be an array");
      let level = 0;
      for (const item of clean.slice(start).matchAll(tokens)) {
        if (item[0] === "[" || item[0] === "{") level++;
        if (item[0] === "]" || item[0] === "}") level--;
        if (level === 0) return text.slice(0, start) + JSON.stringify(plugins, null, 2) +
          text.slice(start + item.index + item[0].length);
      }
      throw Error("Unclosed plugins array");
    }
    if (t === "{" || t === "[") depth++;
    else depth--;
  }
  const start = clean.indexOf("{") + 1;
  return text.slice(0, start) + '\n  "plugins": ' + JSON.stringify(plugins, null, 2) +
    (Object.keys(data).length ? "," : "") + "\n" + text.slice(start);
}

export function openCodeConfigPath() {
  const directory = process.env.OPENCODE_CONFIG_DIR ||
    path.join(process.env.XDG_CONFIG_HOME || path.join(os.homedir(), ".config"), "opencode");
  const candidates = ["opencode.jsonc", "opencode.json"].map(name => path.join(directory, name));
  if (candidates.every(file => fs.existsSync(file))) {
    throw Error("Both opencode.json and opencode.jsonc exist. Choose one configuration before connecting.");
  }
  return candidates.find(file => fs.existsSync(file)) ?? candidates[1];
}

export function configureOpenCode(pluginPath, uninstall = false) {
  if (process.env.OPENCODE_CONFIG) throw Error("Custom OPENCODE_CONFIG detected. Add the Notch plugin in that configuration manually.");
  const file = openCodeConfigPath();
  let exists = false;
  try {
    if (!fs.lstatSync(file).isFile()) throw Error("Configuration must be a regular file, not a symlink");
    exists = true;
  } catch (error) { if (error.code !== "ENOENT") throw error; }
  const previous = exists ? fs.readFileSync(file, "utf8") : '{\n  "$schema": "https://opencode.ai/config.json"\n}\n';
  const updated = updatePlugins(previous, pluginPath, uninstall);
  if (updated === previous) return file;
  fs.mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
  if (exists) fs.copyFileSync(file, `${file}.notch-${Date.now()}-${randomUUID()}.bak`, fs.constants.COPYFILE_EXCL);
  const temporary = `${file}.notch-${randomUUID()}.tmp`;
  try {
    fs.writeFileSync(temporary, updated, { flag: "wx", mode: 0o600 });
    if ((exists && fs.readFileSync(file, "utf8") !== previous) || (!exists && fs.existsSync(file))) {
      throw Error("Configuration changed while connecting. Retry.");
    }
    fs.renameSync(temporary, file);
  } finally { if (fs.existsSync(temporary)) fs.unlinkSync(temporary); }
  return file;
}
