// Accounts and quick match against a running server (local by default):
// gamertag rules, country, names in duels, matchmaking, account deletion.
//   node test/account.mjs
//   NAKAMA_URL=https://... NAKAMA_SERVER_KEY=... node test/account.mjs
const BASE = process.env.NAKAMA_URL || "http://127.0.0.1:7350";
const KEY = process.env.NAKAMA_SERVER_KEY || "longbow-local-key";
const run = Date.now().toString(36).slice(-5);
let failures = 0;
const check = (ok, what) => { console.log((ok ? "ok   " : "FAIL ") + what); if (!ok) failures++; };

async function auth(deviceId) {
  const r = await fetch(`${BASE}/v2/account/authenticate/device?create=true`, {
    method: "POST", headers: { Authorization: "Basic " + btoa(KEY + ":"), "Content-Type": "application/json" },
    body: JSON.stringify({ id: deviceId }),
  }).then((x) => x.json());
  if (!r.token) throw new Error(JSON.stringify(r));
  return r.token;
}

async function rpc(token, id, body) {
  const r = await fetch(`${BASE}/v2/rpc/${id}`, {
    method: "POST", headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
    body: JSON.stringify(JSON.stringify(body || {})),
  }).then((x) => x.json());
  return r.payload ? JSON.parse(r.payload) : r;
}

function socket(token) {
  const ws = new WebSocket(`${BASE.replace(/^http/, "ws")}/ws?lang=en&status=false&token=${token}`);
  const s = { ws, inbox: [], waiters: [] };
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    const w = s.waiters.find((x) => x.test(m));
    if (w) { s.waiters.splice(s.waiters.indexOf(w), 1); w.res(m); } else s.inbox.push(m);
  };
  s.open = new Promise((res) => (ws.onopen = res));
  s.next = (test, ms = 20000) => {
    const hit = s.inbox.find(test);
    if (hit) { s.inbox.splice(s.inbox.indexOf(hit), 1); return Promise.resolve(hit); }
    return new Promise((res, rej) => { s.waiters.push({ test, res }); setTimeout(() => rej(new Error("timed out")), ms); });
  };
  s.send = (env) => ws.send(JSON.stringify(env));
  return s;
}

const a = await auth(`acct-test-a-${run}-0000`), b = await auth(`acct-test-b-${run}-0000`);
const tagA = `Tester_${run}`;

check((await rpc(a, "get_profile")).gamertag === null, "new account has no gamertag yet");
check((await rpc(a, "set_profile", { gamertag: "ab", country: "CA" })).error === "invalid", "too-short gamertag refused");
check((await rpc(a, "set_profile", { gamertag: "has space", country: "CA" })).error === "invalid", "gamertag with a space refused");
check((await rpc(a, "set_profile", { gamertag: "Sh1tShot", country: "CA" })).error === "not_allowed", "blocked word refused");
check((await rpc(a, "set_profile", { gamertag: tagA, country: "Canada" })).error === "bad_country", "bad country refused");
check((await rpc(a, "set_profile", { gamertag: tagA, country: "ca" })).gamertag === tagA, "gamertag set");
const pa = await rpc(a, "get_profile");
check(pa.gamertag === tagA && pa.country === "CA", "profile reads back with casing kept");
check((await rpc(b, "set_profile", { gamertag: tagA.toUpperCase(), country: "IN" })).error === "taken", "same gamertag in other casing is taken");
check((await rpc(b, "set_profile", { gamertag: `Other_${run}`, country: "IN" })).gamertag === `Other_${run}`, "second player sets theirs");

// Quick match: both ask the matchmaker, get paired, join, and see each other's gamertag and country.
const sa = socket(a), sb = socket(b);
await Promise.all([sa.open, sb.open]);
const ticket = { matchmaker_add: { min_count: 2, max_count: 2, query: "+properties.mode:quick", string_properties: { mode: "quick" } } };
sa.send({ cid: "1", ...ticket }); sb.send({ cid: "1", ...ticket });
const [ma, mb] = await Promise.all([sa.next((m) => m.matchmaker_matched, 60000), sb.next((m) => m.matchmaker_matched, 60000)]);
const matchId = ma.matchmaker_matched.match_id;
check(!!matchId && matchId === mb.matchmaker_matched.match_id, "matchmaker paired the two players into one match");
sa.send({ cid: "2", match_join: { match_id: matchId, metadata: { name: "SPOOF", hat: "none", avatar: "{}" } } });
sb.send({ cid: "2", match_join: { match_id: matchId, metadata: { name: "SPOOF", hat: "none", avatar: "{}" } } });
const start = await sa.next((m) => m.match_data && Number(m.match_data.op_code) === 10);
const body = JSON.parse(Buffer.from(start.match_data.data, "base64").toString());
const names = body.seats.map((s) => s.name).sort();
check(JSON.stringify(names) === JSON.stringify([tagA, `Other_${run}`].sort()), "duel uses gamertags, not names the app sent");
check(body.seats.some((s) => s.country === "CA") && body.seats.some((s) => s.country === "IN"), "duel carries both countries");
check(body.challenge === "medium" && body.roundsToWin === 1, "quick match is medium, one round");

// Tampered shots are refused; only a legal shot from the right player counts.
const seatOf = (tok) => body.seats.findIndex((s) => s.userId === JSON.parse(Buffer.from(tok.split(".")[1], "base64url").toString()).uid);
const shooterSock = seatOf(a) === body.firstShooter ? sa : sb, otherSock = shooterSock === sa ? sb : sa;
const shot = (s, b) => s.send({ match_data_send: { match_id: matchId, op_code: "1", data: Buffer.from(JSON.stringify(b)).toString("base64") } });
const isOp = (op) => (m) => m.match_data && Number(m.match_data.op_code) === op;
shot(shooterSock, { turn: body.turn, angleTenths: 450, powerPermille: 5000 });
check(!!(await shooterSock.next(isOp(15), 5000).catch(() => null)), "impossible power rejected");
shot(shooterSock, { turn: body.turn + 7, angleTenths: 450, powerPermille: 600 });
check(!!(await shooterSock.next(isOp(15), 5000).catch(() => null)), "wrong turn number rejected");
shot(otherSock, { turn: body.turn, angleTenths: 450, powerPermille: 600 });
check(!!(await otherSock.next(isOp(15), 5000).catch(() => null)), "shooting out of turn rejected");
shot(shooterSock, { turn: body.turn, angleTenths: 450, powerPermille: 600 });
const legal = await shooterSock.next(isOp(11), 10000).catch(() => null);
check(!!legal && JSON.parse(Buffer.from(legal.match_data.data, "base64").toString()).turn === body.turn, "legal shot accepted");

// A third player can't wander into someone else's quick match.
const c = await auth(`acct-test-c-${run}-0000`);
const sc = socket(c); await sc.open;
sc.send({ cid: "9", match_join: { match_id: matchId } });
const refused = await sc.next((m) => m.cid === "9");
check(!!refused.error, "outsider can't join a quick match");
for (const s of [sa, sb, sc]) s.ws.close();

// Push tokens: junk refused, a real-looking one stored.
check((await rpc(a, "register_push", { token: "nope" })).error === "bad_token", "junk push token refused");
check((await rpc(a, "register_push", { token: "ab".repeat(32), sandbox: true })).ok === true, "push token registered");

// The creator steps away (socket gone) while waiting; the friend joins by code;
// the creator comes back by match id and the duel starts.
{
  const created = await rpc(a, "create_duel", { challenge: "easy" });
  let s1 = socket(a); await s1.open;
  s1.send({ cid: "1", match_join: { match_id: created.matchId } });
  await s1.next((m) => m.cid === "1");
  s1.ws.close();
  await new Promise((r) => setTimeout(r, 1500));
  const joined = await rpc(b, "join_duel", { code: created.code });
  check(joined.matchId === created.matchId, "code still works after the creator stepped away");
  const s2 = socket(b); await s2.open;
  s2.send({ cid: "1", match_join: { match_id: joined.matchId } });
  await s2.next((m) => m.cid === "1");
  s1 = socket(a); await s1.open;
  s1.send({ cid: "1", match_join: { match_id: created.matchId } });
  const st = await s1.next((m) => m.match_data && Number(m.match_data.op_code) === 10, 10000).catch(() => null);
  check(!!st, "creator rejoins and the duel starts");
  s1.ws.close(); s2.ws.close();
}

// Deleting an account removes it; the same device id then starts over.
check((await rpc(a, "delete_account")).deleted === true, "account deleted");
const again = await auth(`acct-test-a-${run}-0000`);
check((await rpc(again, "get_profile")).gamertag === null, "same device starts a fresh account");
check((await rpc(b, "set_profile", { gamertag: tagA, country: "IN" })).gamertag === tagA, "deleted player's gamertag is free again");
for (const t of [again, b, c]) await rpc(t, "delete_account");

console.log(failures ? `${failures} FAILED` : "all account checks passed");
process.exit(failures ? 1 : 0);
