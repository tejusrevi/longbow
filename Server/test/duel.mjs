// End-to-end duel against the running Nakama: two scripted players connect
// over WebSockets, one creates a duel, the other joins with the code, and they
// play a whole match. Each keeps its own MatchEngine copy (the same module)
// and checks every server result against it.
import { readFileSync } from "node:fs";
import vm from "node:vm";

// Local dev server by default; against the hosted one:
//   NAKAMA_URL=https://longbow-duel.canadacentral.cloudapp.azure.com NAKAMA_SERVER_KEY=... node test/duel.mjs
const BASE = process.env.NAKAMA_URL || "http://127.0.0.1:7350";
const KEY = process.env.NAKAMA_SERVER_KEY || "longbow-local-key";
const OP = { SHOT: 1, READY: 2, START: 10, RESULT: 11, END: 12, REJECT: 15 };
const mod = readFileSync(new URL("../modules/index.js", import.meta.url), "utf8");

async function auth(id) {
  const r = await fetch(`${BASE}/v2/account/authenticate/device?create=true`, {
    method: "POST", headers: { Authorization: "Basic " + btoa(KEY + ":"), "Content-Type": "application/json" },
    body: JSON.stringify({ id }) });
  return (await r.json()).token;
}
async function rpc(token, id, body) {
  const r = await fetch(`${BASE}/v2/rpc/${id}`, { method: "POST",
    headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" }, body: JSON.stringify(JSON.stringify(body)) });
  const j = await r.json();
  if (!j.payload) throw new Error(JSON.stringify(j));
  return JSON.parse(j.payload);
}

function player(name, token) {
  const ctx = vm.createContext({});
  vm.runInContext(mod, ctx);
  const ws = new WebSocket(`${BASE.replace(/^http/, "ws")}/ws?lang=en&status=false&token=${token}`);
  const p = { name, ws, ctx, seat: -1, matchId: null, mismatches: 0, results: 0, ended: null, cid: 0, waiters: {} };
  p.send = (env) => { const cid = String(++p.cid); ws.send(JSON.stringify({ cid, ...env })); return new Promise((res) => (p.waiters[cid] = res)); };
  p.sendData = (op, body) => ws.send(JSON.stringify({ match_data_send: { match_id: p.matchId, op_code: String(op),
    data: Buffer.from(JSON.stringify(body)).toString("base64") } }));
  p.open = new Promise((res) => (ws.onopen = res));
  p.done = new Promise((res) => (p.finish = res));
  ws.onmessage = (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.cid && p.waiters[msg.cid]) { p.waiters[msg.cid](msg); delete p.waiters[msg.cid]; return; }
    if (!msg.match_data) return;
    const op = Number(msg.match_data.op_code);
    const body = JSON.parse(Buffer.from(msg.match_data.data, "base64").toString());
    if (op === OP.START) {
      p.seat = body.seats.findIndex((s) => s && s.userId === p.userId);
      ctx.start = body;
      vm.runInContext(`var engine = new MatchEngine(start.seed, start.arena, start.roundsToWin, start.firstShooter, start.challenge);`, ctx);
      p.maybeShoot();
    } else if (op === OP.RESULT) {
      ctx.res = body;
      const ok = vm.runInContext(`(function () {
        if (engine.state.phase.kind === "roundOver") engine.startNextRound();
        var r = engine.submit(res.angleTenths, res.powerPermille);
        return r.turn === res.turn && JSON.stringify(r.health) === JSON.stringify(res.health) && JSON.stringify(r.events) === JSON.stringify(res.events);
      })()`, ctx);
      p.results++;
      if (!ok) { p.mismatches++; console.log(p.name, "MISMATCH at turn", body.turn); }
      p.maybeShoot();
    } else if (op === OP.END) {
      p.ended = body; p.finish();
    } else if (op === OP.REJECT) {
      console.log(p.name, "rejected", body);
    }
  };
  p.maybeShoot = () => {
    const mine = vm.runInContext(`(function () {
      if (engine.state.phase.kind === "roundOver") engine.startNextRound();
      return engine.state.phase.kind === "awaitingShot" && engine.state.currentShooter === ${p.seat} ? engine.state.turn : -1; })()`, ctx);
    if (mine < 0) return;
    // A decent shot: search for a hit with the same engine (like a sharp player would).
    const shot = vm.runInContext(`(function () {
      var c = engine.state.conditions, s = engine.state.currentShooter;
      for (var a = 150; a <= 700; a += 25) for (var pw = 300; pw <= 1000; pw += 20) {
        var o = simulateShot(a, pw, s, c); if (o.impact === "archer" && o.index === 1 - s) return [a, pw]; }
      return [450, 800]; })()`, ctx);
    setTimeout(() => p.sendData(OP.SHOT, { turn: mine, angleTenths: shot[0], powerPermille: shot[1] }), 30);
  };
  return p;
}

const [ta, tb] = await Promise.all([auth("duel-test-alpha-0001"), auth("duel-test-bravo-0001")]);
const a = player("alpha", ta), b = player("bravo", tb);
await Promise.all([a.open, b.open]);
const created = await rpc(ta, "create_duel", { challenge: "hard" });
console.log("created duel", created.code);
const joined = await rpc(tb, "join_duel", { code: created.code.toLowerCase() });
const bad = await rpc(tb, "join_duel", { code: "ZZZZ" });
console.log("bad code ->", bad.error);
for (const [p, tok] of [[a, ta], [b, tb]]) {
  p.matchId = joined.matchId;
  p.userId = JSON.parse(Buffer.from(tok.split(".")[1], "base64url").toString()).uid;
}
const ja = await a.send({ match_join: { match_id: joined.matchId, metadata: { name: "ALPHA", hat: "crown", avatar: "{}" } } });
const jb = await b.send({ match_join: { match_id: joined.matchId, metadata: { name: "BRAVO", hat: "none", avatar: "{}" } } });
if (ja.error || jb.error) { console.log(ja.error, jb.error); process.exit(1); }
const timeout = setTimeout(() => { console.log("timed out"); process.exit(1); }, 120000);
await Promise.all([a.done, b.done]);
clearTimeout(timeout);
console.log(`seats alpha=${a.seat} bravo=${b.seat}; ${a.results} results; winner seat ${a.ended.winner} (${a.ended.reason}); ` +
  `mismatches alpha=${a.mismatches} bravo=${b.mismatches}`);
a.ws.close(); b.ws.close();
process.exit(a.mismatches + b.mismatches === 0 && a.ended.winner === b.ended.winner ? 0 : 1);
