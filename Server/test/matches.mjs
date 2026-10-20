// Replays every match in Shared/golden_matches.json through the server's
// MatchEngine (the exact module Nakama loads) and checks each turn: impact,
// damage, health, events, wind and knockback, bit for bit.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const traces = JSON.parse(readFileSync(new URL("../../Shared/golden_matches.json", import.meta.url)));
const ctx = vm.createContext({});
vm.runInContext(readFileSync(new URL("../modules/index.js", import.meta.url), "utf8"), ctx);

let bad = 0, turns = 0;
for (const [m, t] of traces.entries()) {
  ctx.t = t;
  const out = vm.runInContext(`(function () {
    var e = new MatchEngine(t.seed, "hills", 2, t.firstShooter, t.challenge);
    var rows = [{ wind: f64Hex(e.state.windWorld), distance: e.state.conditions.distance }];
    for (var i = 0; i < t.turns.length; i++) {
      if (e.state.phase.kind === "roundOver") e.startNextRound();
      var r = e.submit(t.turns[i].angleTenths, t.turns[i].powerPermille);
      var o = r.outcome;
      rows.push({
        impact: o.impact === "archer" ? "archer:" + o.index + ":" + o.part : o.impact === "obstacle" ? "obstacle:" + o.index : o.impact,
        xBits: f64Hex(o.x), damage: r.damage, health: r.health, events: r.events, windBits: f64Hex(e.state.windWorld),
        offsetBits: e.state.conditions.archerOffsets.map(f64Hex), nextShooter: e.state.currentShooter, round: e.state.round,
      });
    }
    return JSON.stringify(rows);
  })()`, ctx);
  const rows = JSON.parse(out);
  if (rows[0].wind !== t.startWindBits || rows[0].distance !== t.startDistance) {
    bad++; console.log(`match ${m}: start differs`, rows[0], t.startWindBits, t.startDistance); continue;
  }
  for (let i = 0; i < t.turns.length; i++) {
    turns++;
    const want = t.turns[i], got = rows[i + 1];
    const keys = ["impact", "xBits", "damage", "health", "events", "windBits", "offsetBits", "nextShooter", "round"];
    const diff = keys.filter((k) => JSON.stringify(want[k]) !== JSON.stringify(got[k]));
    if (diff.length) {
      bad++;
      console.log(`match ${m} turn ${i}: ${diff.map((k) => `${k} want ${JSON.stringify(want[k])} got ${JSON.stringify(got[k])}`).join("; ")}`);
      break;
    }
  }
}
console.log(`${traces.length} matches, ${turns} turns checked, ${bad} mismatching`);
process.exit(bad ? 1 : 0);
