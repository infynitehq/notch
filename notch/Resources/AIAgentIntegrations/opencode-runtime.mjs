import path from "node:path";
import { makeEvent, sendEvent } from "./bridge.mjs";
import { eventTypes, normalizeOpenCodeEvent } from "./opencode-events.mjs";

export function startCompanion(ctx, { send = sendEvent } = {}) {
    const controller = new AbortController();
    const sessions = new Map();
    let stopped = false;
    async function observe(event) {
      const mapped = normalizeOpenCodeEvent(event);
      if (!mapped) return;
      let session = sessions.get(mapped.sessionID);
      if (!session) {
        if (sessions.size >= 64) return;
        // Event location is preferred: one server can host several projects.
        let directory = event.location?.directory;
        if (!directory) {
          try {
            directory = (await ctx.session.get(
              { sessionID: mapped.sessionID }, { signal: AbortSignal.timeout(1000) },
            )).location?.directory;
          }
          catch { /* Project label is optional; never substitute another session's location. */ }
        }
        session = { directory, pending: new Set(), active: false, lastSeen: Date.now() };
        sessions.set(mapped.sessionID, session);
      }
      if (mapped.kind === "started") session.pending.clear();
      if (mapped.requestChange === "add" && mapped.requestID && session.pending.size < 128) {
        session.pending.add(mapped.requestID);
      }
      if (mapped.requestChange === "remove") session.pending.delete(mapped.requestID);
      const kind = mapped.kind === "activity" && session.pending.size ? "attention" : mapped.kind;
      session.active = ["started", "activity", "attention"].includes(kind);
      session.lastSeen = Date.now();
      if (!session.active) session.pending.clear();
      if (!stopped) await send(makeEvent("opencode", mapped.sessionID, kind, {
        directory: session.directory ? path.normalize(session.directory) : undefined,
        eventID: event.id,
      }));
    }
    // Heartbeats only renew observed active sessions. A crashed plugin stops renewing them.
    const heartbeat = setInterval(() => {
      for (const [id, session] of sessions) {
        if (session.active) {
          void send(makeEvent("opencode", id, "heartbeat"));
        } else if (Date.now() - session.lastSeen > 60_000) {
          sessions.delete(id);
        }
      }
    }, 30_000);
    heartbeat.unref?.();
    const consume = async () => {
      let delay = 1000;
      while (!stopped) {
        try {
          for await (const event of ctx.event.subscribe({ types: eventTypes, signal: controller.signal })) {
            if (stopped) break;
            await observe(event);
            delay = 1000;
          }
        } catch { /* A transient event-stream error must not take down OpenCode. */ }
        if (stopped) break;
        // A stream interruption invalidates our view of liveness. Don't keep lying via heartbeats.
        for (const [id, session] of sessions) {
          if (session.active) await send(makeEvent("opencode", id, "ended"));
        }
        sessions.clear();
        await new Promise((resolve) => {
          const timer = setTimeout(done, delay);
          function done() {
            clearTimeout(timer);
            controller.signal.removeEventListener("abort", done);
            resolve();
          }
          controller.signal.addEventListener("abort", done, { once: true });
          if (controller.signal.aborted) done();
        });
        delay = Math.min(delay * 2, 10_000);
      }
    };
    void consume();
    return async () => {
      stopped = true;
      clearInterval(heartbeat);
      controller.abort();
      await Promise.allSettled([...sessions].filter(([, session]) => session.active)
         .map(([id]) => send(makeEvent("opencode", id, "ended"))));
    };
}
