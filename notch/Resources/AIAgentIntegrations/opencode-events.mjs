export const eventTypes = [
  "session.execution.started", "session.execution.succeeded",
  "session.execution.failed", "session.execution.interrupted", "session.deleted",
  "session.tool.called", "permission.asked", "permission.replied",
  "form.created", "form.replied", "form.cancelled",
];

/** Only status metadata crosses this interface, never event bodies. */
export function normalizeOpenCodeEvent(event) {
  const data = event?.data;
  if (!data || !eventTypes.includes(event.type)) return;
  const sessionID = data.sessionID ?? data.form?.sessionID;
  if (typeof sessionID !== "string") return;
  const kind = ({
    "session.execution.started": "started",
    "session.execution.succeeded": "completed",
    "session.execution.failed": "failed",
    "session.execution.interrupted": "ended",
    "session.deleted": "ended",
    "session.tool.called": "activity",
    "permission.asked": "attention",
    "permission.replied": "activity",
    "form.created": "attention",
    "form.replied": "activity",
    "form.cancelled": "activity",
  })[event.type];
  return {
    sessionID, kind,
    requestID: data.requestID ?? data.form?.id ?? data.id,
    requestChange: ["permission.asked", "form.created"].includes(event.type) ? "add"
      : ["permission.replied", "form.replied", "form.cancelled"].includes(event.type) ? "remove" : undefined,
  };
}
