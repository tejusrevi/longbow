// Runs every shot in Shared/golden_shots.json through the server physics
// (the exact module Nakama loads) and checks the result bit for bit.
//   node test/golden.mjs           — in Node
//   node test/golden.mjs --nakama  — through the running Nakama server
import { readFileSync } from "node:fs";
import vm from "node:vm";

const golden = JSON.parse(readFileSync(new URL("../../Shared/golden_shots.json", import.meta.url)));
const reqs = golden.shots.map((s) => ({ seed: s.seed, arena: s.arena, shooter: s.shooter,
  angleTenths: s.angleTenths, powerPermille: s.powerPermille }));

function bits(x) {
  const b = new DataView(new ArrayBuffer(8));
  b.setFloat64(0, x);
  return "0x" + b.getBigUint64(0).toString(16).toUpperCase().padStart(16, "0");
}

let results;
if (process.argv.includes("--nakama")) {
  const base = "http://127.0.0.1:7350";
  // simulate_shots is server-to-server only: call it with the runtime http_key.
  const httpKey = process.env.NAKAMA_HTTP_KEY || "longbow-local-http";
  // Small batches: the HTTP gateway caps request size.
  results = [];
  for (let i = 0; i < reqs.length; i += 40) {
    const res = await fetch(base + "/v2/rpc/simulate_shots?http_key=" + encodeURIComponent(httpKey), {
      method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify(JSON.stringify(reqs.slice(i, i + 40))),
    }).then((r) => r.json());
    if (!res.payload) { console.error(res); process.exit(1); }
    results.push(...JSON.parse(res.payload));
  }
} else {
  const ctx = vm.createContext({});
  vm.runInContext(readFileSync(new URL("../modules/index.js", import.meta.url), "utf8"), ctx);
  ctx.reqs = reqs;
  results = vm.runInContext(`reqs.map(function (r) {
    return simulateShot(r.angleTenths, r.powerPermille, r.shooter, generateConditions(r.seed, arenaProfile(r.arena)));
  })`, ctx);
}

let bad = 0;
golden.shots.forEach((s, i) => {
  const g = s.expected, r = results[i];
  const ok = r.impact === g.impact && (r.index ?? null) === (g.index ?? null) && (r.part ?? null) === (g.part ?? null)
    && r.steps === g.steps && bits(r.x) === g.xBits && bits(r.y) === g.yBits;
  if (!ok) {
    bad++;
    if (bad <= 5) console.log("MISMATCH", s.id, JSON.stringify(g), JSON.stringify(r), bits(r.x), bits(r.y));
  }
});
console.log(`${golden.shots.length - bad}/${golden.shots.length} golden shots match`);
process.exit(bad ? 1 : 0);
