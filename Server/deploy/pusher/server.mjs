// Sends Apple push notifications for the game server. Nakama's runtime
// can't sign ES256 tokens or speak HTTP/2, so it posts here instead:
//   POST /send  {deviceToken, sandbox, title, body, data, collapseId}
// Only reachable inside the Docker network (no published port), and every
// request must carry the shared secret. No dependencies: Node's http2+crypto.
import http from "node:http";
import http2 from "node:http2";
import crypto from "node:crypto";
import fs from "node:fs";

const KEY_ID = process.env.APNS_KEY_ID;
const TEAM_ID = process.env.APNS_TEAM_ID;
const TOPIC = process.env.APNS_TOPIC;
const SECRET = process.env.PUSH_SECRET;
const key = crypto.createPrivateKey(fs.readFileSync(process.env.APNS_KEY_FILE));

const b64url = (buf) => Buffer.from(buf).toString("base64url");

// Apple wants a fresh provider token at most hourly and at least every 20 min apart.
let jwt = null, jwtAt = 0;
function providerToken() {
  if (jwt && Date.now() - jwtAt < 40 * 60 * 1000) return jwt;
  const head = b64url(JSON.stringify({ alg: "ES256", kid: KEY_ID }));
  const claims = b64url(JSON.stringify({ iss: TEAM_ID, iat: Math.floor(Date.now() / 1000) }));
  const sig = crypto.sign("sha256", Buffer.from(`${head}.${claims}`), { key, dsaEncoding: "ieee-p1363" });
  jwt = `${head}.${claims}.${b64url(sig)}`;
  jwtAt = Date.now();
  return jwt;
}

const sessions = {};
function apns(sandbox) {
  const host = sandbox ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
  const s = sessions[host];
  if (s && !s.closed && !s.destroyed) return s;
  const fresh = http2.connect(host);
  fresh.on("error", () => fresh.close());
  fresh.on("goaway", () => fresh.close());
  sessions[host] = fresh;
  return fresh;
}

function send({ deviceToken, sandbox, title, body, data, collapseId }) {
  return new Promise((resolve) => {
    if (!/^[0-9a-f]{64,200}$/i.test(deviceToken || "")) return resolve({ status: 400, reason: "BadDeviceToken" });
    const payload = JSON.stringify({ aps: { alert: { title, body }, sound: "default" }, ...(data || {}) });
    const headers = {
      ":method": "POST", ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${providerToken()}`, "apns-topic": TOPIC, "apns-push-type": "alert",
      "apns-priority": "10", "apns-expiration": String(Math.floor(Date.now() / 1000) + 600),
      ...(collapseId ? { "apns-collapse-id": String(collapseId).slice(0, 64) } : {}),
    };
    const req = apns(!!sandbox).request(headers);
    let status = 0, text = "";
    req.on("response", (h) => (status = h[":status"]));
    req.on("data", (c) => (text += c));
    req.on("end", () => {
      let reason = "";
      try { reason = JSON.parse(text).reason || ""; } catch {}
      resolve({ status, reason });
    });
    req.on("error", (e) => resolve({ status: 502, reason: String(e.message || e) }));
    req.setTimeout(8000, () => { req.close(); resolve({ status: 504, reason: "Timeout" }); });
    req.end(payload);
  });
}

http.createServer((req, res) => {
  if (req.method !== "POST" || req.url !== "/send" || req.headers["x-push-secret"] !== SECRET) {
    res.writeHead(404).end();
    return;
  }
  let raw = "";
  req.on("data", (c) => { raw += c; if (raw.length > 8192) req.destroy(); });
  req.on("end", async () => {
    let msg;
    try { msg = JSON.parse(raw); } catch { res.writeHead(400).end(); return; }
    const out = await send(msg);
    console.log(`push ${out.status} ${out.reason || "ok"}`);
    res.writeHead(200, { "content-type": "application/json" }).end(JSON.stringify(out));
  });
}).listen(8080, () => console.log("pusher listening on 8080"));
