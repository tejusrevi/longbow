// Push notifications (A7.4). The app registers its APNs device token; the
// server posts alerts to the pusher sidecar (Server/deploy/pusher), which
// signs and sends them to Apple. Without PUSH_URL (local dev) it's a no-op.

const PUSH_COLLECTION = "push";

function rpcRegisterPush(ctx: any, logger: any, nk: any, payload: string): string {
  const req = JSON.parse(payload || "{}");
  const token = String(req.token || "");
  if (!/^[0-9a-f]{64,200}$/i.test(token)) return JSON.stringify({ error: "bad_token" });
  nk.storageWrite([{ collection: PUSH_COLLECTION, key: "device", userId: ctx.userId,
                     value: { token: token, sandbox: !!req.sandbox }, permissionRead: 0, permissionWrite: 0 }]);
  return JSON.stringify({ ok: true });
}

/// Sends an alert to a player's phone, if they allowed notifications.
/// A token Apple says is dead is forgotten.
function notifyPlayer(ctx: any, logger: any, nk: any, userId: string, title: string, body: string, data: any): void {
  const env = ctx.env || {};
  if (!env.PUSH_URL) return;
  const found = nk.storageRead([{ collection: PUSH_COLLECTION, key: "device", userId: userId }]);
  if (found.length === 0) return;
  const device = found[0].value;
  try {
    const res = nk.httpRequest(env.PUSH_URL, "post", { "Content-Type": "application/json", "X-Push-Secret": env.PUSH_SECRET },
      JSON.stringify({ deviceToken: device.token, sandbox: device.sandbox, title: title, body: body, data: data,
                       collapseId: data && data.matchId }), 5000);
    const out = JSON.parse(res.body || "{}");
    if (out.status === 410 || out.reason === "BadDeviceToken" || out.reason === "Unregistered") {
      nk.storageDelete([{ collection: PUSH_COLLECTION, key: "device", userId: userId }]);
    } else if (out.status !== 200) {
      logger.warn("push to %s failed: %s %s", userId, out.status, out.reason);
    }
  } catch (err) {
    logger.warn("push to %s failed: %s", userId, String(err));
  }
}
