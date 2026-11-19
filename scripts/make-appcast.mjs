import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import { execFileSync } from "node:child_process";

const [app, archive, signature, destination] = process.argv.slice(2);
if (!destination) throw Error("Usage: node scripts/make-appcast.mjs app archive signature output.xml");
const read = key => execFileSync("/usr/libexec/PlistBuddy",
  ["-c", `Print :${key}`, path.join(app, "Contents/Info.plist")], { encoding: "utf8" }).trim();
if (read("CFBundleIdentifier") !== "in.infynite.notch") throw Error("Unexpected application identity");
const publicKey = crypto.createPublicKey({
  key: Buffer.concat([Buffer.from("302a300506032b6570032100", "hex"), Buffer.from(read("SUPublicEDKey"), "base64")]),
  format: "der", type: "spki",
});
const bytes = fs.readFileSync(archive);
if (!crypto.verify(null, bytes, publicKey, Buffer.from(signature, "base64"))) {
  throw Error("Update signature does not match the public key built into Notch");
}
const escape = value => String(value).replaceAll("&", "&amp;").replaceAll('"', "&quot;")
  .replaceAll("<", "&lt;").replaceAll(">", "&gt;");
const version = read("CFBundleShortVersionString");
const build = read("CFBundleVersion");
const filename = path.basename(archive);
fs.writeFileSync(destination, `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Notch updates</title>
    <link>https://github.com/infynitehq/notch/releases</link>
    <description>Notch by infynite</description>
    <language>en</language>
    <item>
      <title>Notch ${escape(version)}</title>
      <pubDate>${new Date().toUTCString()}</pubDate>
      <sparkle:minimumSystemVersion>${escape(read("LSMinimumSystemVersion"))}</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/infynitehq/notch/releases/tag/v${escape(version)}</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/infynitehq/notch/releases/download/v${escape(version)}/${escape(filename)}"
        sparkle:version="${escape(build)}" sparkle:shortVersionString="${escape(version)}"
        sparkle:edSignature="${escape(signature)}" length="${bytes.length}" type="application/octet-stream"/>
    </item>
  </channel>
</rss>
`);
console.log("Verified the update signature and generated " + destination);
