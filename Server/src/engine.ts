// Match rules: a line-by-line port of LongbowCore's MatchEngine (spec A6.4,
// A6.5), plus ShotSearch.isHittable and RoundConditions.generatePlayable that
// it relies on. Shared/golden_matches.json proves it plays out exactly like
// the app, turn by turn.

const RULES = { roundsToWin: 1, maxShotsPerPlayerPerRound: 20, startHealth: 100, shotTimeLimitSeconds: 20 };
const DAMAGE: { [part: string]: number } = { head: 50, body: 25, legs: 15 };
const NEAR_MISS_DISTANCE = 3;

interface Challenge { windScale: number; knockMin: number; knockMax: number; maxKnockback: number }
const CHALLENGES: { [id: string]: Challenge } = {
  easy: { windScale: 0.5, knockMin: 15, knockMax: 25, maxKnockback: 6 },
  medium: { windScale: 1, knockMin: 30, knockMax: 45, maxKnockback: 10 },
  hard: { windScale: 1.5, knockMin: 50, knockMax: 70, maxKnockback: 14 },
};

/// Swift's `.rounded()`: halves round away from zero (Math.round does not, for negatives).
function roundSwift(x: number): number { return x < 0 ? -Math.round(-x) : Math.round(x); }

function hexU64(v: U64): string { return "0x" + ("00000000" + v.hi.toString(16)).slice(-8).toUpperCase() + ("00000000" + v.lo.toString(16)).slice(-8).toUpperCase(); }

// --- ShotSearch.isHittable --------------------------------------------------

function bodyCenter(feet: Vec2, s: number): Vec2 { return { x: feet.x, y: feet.y + 1.2 * s }; }

/// True when some shot from `shooter` can hit the other archer (angle step 3°,
/// binary search on power). Order of angles doesn't change the yes/no answer.
function isHittable(c: RoundConditions, shooter: number): boolean {
  const target = 1 - shooter;
  const dir = facing(shooter);
  const aim = bodyCenter(archerPosition(c, target), PHYSICS.archerScale);
  for (let a = AIM.minAngleTenths; a <= AIM.maxAngleTenths; a += 30) {
    let lo = 0, hi = 1000;
    const far = simulateShot(a, hi, shooter, c);
    if (far.impact === "archer" && far.index === target) return true;
    if ((far.x - aim.x) * dir < 0) continue;
    for (let k = 0; k < 11; k++) {
      const mid = Math.floor((lo + hi) / 2);
      const e = simulateShot(a, mid, shooter, c);
      if (e.impact === "archer" && e.index === target) return true;
      if ((e.x - aim.x) * dir < 0) lo = mid; else hi = mid;
      if (hi - lo <= 1) break;
    }
  }
  return false;
}

function generatePlayable(seed: U64, arena: ArenaProfile): RoundConditions {
  let last = generateConditions(hexU64(seed), arena);
  if (isHittable(last, 0)) return last;
  for (let attempt = 1; attempt <= 12; attempt++) {
    last = generateConditions(hexU64(hash64(seed, [u64(0, 0xF1), u64FromInt(attempt)])), arena);
    if (isHittable(last, 0)) return last;
  }
  last.windRelative = 0;
  last.obstacles = [];
  return last;
}

function roundSeed(matchSeed: U64, round: number, suddenDeath: number): U64 {
  return hash64(matchSeed, [u64FromInt(round), u64FromInt(suddenDeath)]);
}

function tossWinner(seed: U64): number { return hash64(seed, [u64(0, 0x7055)]).lo & 1; }

// --- Miss distance ----------------------------------------------------------

function shapeDistance(s: HitShape, p: Vec2): number {
  if (s.kind === "circle") {
    const dx = p.x - s.c.x, dy = p.y - s.c.y;
    return Math.max(0, Math.sqrt(dx * dx + dy * dy) - s.r);
  }
  const dx = Math.max(Math.max(s.min.x - p.x, 0), p.x - s.max.x);
  const dy = Math.max(Math.max(s.min.y - p.y, 0), p.y - s.max.y);
  return Math.sqrt(dx * dx + dy * dy);
}

function hitboxDistance(p: Vec2, feet: Vec2): number {
  const shapes = hitboxes(feet, PHYSICS.archerScale);
  let best = Infinity;
  for (let i = 0; i < shapes.length; i++) best = Math.min(best, shapeDistance(shapes[i][1], p));
  return best;
}

// --- Engine -----------------------------------------------------------------

type Phase = { kind: "awaitingShot" } | { kind: "roundOver"; winner: number } | { kind: "matchOver"; winner: number };

/// Events, encoded like the app's golden traces: "nextTurn:1:false", "windChanged:0x…".
type TurnEvent = string;

interface MatchState {
  seed: U64; arena: string; roundsToWin: number; challenge: string;
  phase: Phase; round: number; roundsWon: number[]; roundFirstShooter: number; health: number[];
  shotsThisRound: number[]; currentShooter: number; turn: number; lastBreath: boolean; pair: number;
  suddenDeath: number; suddenDeathShots: Array<{ missDistance: number; damage: number } | null>;
  conditions: RoundConditions; windWorld: number; hitsLanded: number[]; headshots: number[];
}

interface TurnReport {
  turn: number; round: number; shooter: number; angleTenths: number; powerPermille: number;
  outcome: ShotOutcome; damagedArcher: number | null; damage: number; health: number[];
  missDistance: number | null; nearMiss: number | null; events: TurnEvent[];
}

function f64Hex(x: number): string {
  // Bit pattern of a double without typed arrays: exact for all finite values.
  if (x === 0) return 1 / x < 0 ? "0x8000000000000000" : "0x0000000000000000";
  const sign = x < 0 ? 1 : 0;
  let v = Math.abs(x);
  let exp = Math.floor(Math.log(v) / Math.LN2);
  if (Math.pow(2, exp) > v) exp--;
  if (Math.pow(2, exp + 1) <= v) exp++;
  let biased = exp + 1023, frac: number;
  if (biased <= 0) { frac = v / Math.pow(2, -1074); biased = 0; } else { frac = (v / Math.pow(2, exp) - 1) * 4503599627370496; }
  const hi = (sign << 31 | biased << 20 | Math.floor(frac / 4294967296)) >>> 0;
  const lo = frac % 4294967296;
  return "0x" + ("00000000" + hi.toString(16)).slice(-8).toUpperCase() + ("00000000" + lo.toString(16)).slice(-8).toUpperCase();
}

class MatchEngine {
  state: MatchState;

  constructor(seedHex: string, arena: string, roundsToWin: number, firstShooter: number, challenge: string) {
    const seed = u64FromHex(seedHex);
    const profile = arenaProfile(arena);
    this.state = {
      seed: seed, arena: arena, roundsToWin: roundsToWin, challenge: challenge,
      phase: { kind: "awaitingShot" }, round: 1, roundsWon: [0, 0], roundFirstShooter: firstShooter,
      health: [RULES.startHealth, RULES.startHealth], shotsThisRound: [0, 0], currentShooter: firstShooter,
      turn: 1, lastBreath: false, pair: 0, suddenDeath: 0, suddenDeathShots: [null, null],
      conditions: generatePlayable(roundSeed(seed, 1, 0), profile), windWorld: 0, hitsLanded: [0, 0], headshots: [0, 0],
    };
    const sign = this.windSign();
    this.state.windWorld = this.fittedWind(this.scaledWind(sign * Math.abs(this.state.conditions.windRelative)));
    this.syncWind();
  }

  private ch(): Challenge { return CHALLENGES[this.state.challenge] || CHALLENGES.medium; }
  private windSign(): number { return (hash64(this.state.seed, [u64(0, 0x5141D)]).lo & 1) === 0 ? 1 : -1; }

  private syncWind(): void { this.state.conditions.windRelative = this.state.windWorld * facing(this.state.currentShooter); }

  private windAllowsHits(world: number): boolean {
    const c: RoundConditions = this.copyConditions();
    for (let shooter = 0; shooter < 2; shooter++) {
      c.windRelative = world * facing(shooter);
      if (!isHittable(c, shooter)) return false;
    }
    return true;
  }

  private copyConditions(): RoundConditions {
    const c = this.state.conditions;
    return { seedHex: c.seedHex, arena: c.arena, distance: c.distance, windRelative: c.windRelative, gravity: c.gravity,
             terrain: c.terrain, obstacles: c.obstacles, archerOffsets: [c.archerOffsets[0], c.archerOffsets[1]] };
  }

  private fittedWind(world: number): number {
    let w = world;
    while (w !== 0 && !this.windAllowsHits(w)) w = w > 0 ? Math.max(0, w - 0.5) : Math.min(0, w + 0.5);
    return w;
  }

  private scaledWind(w: number): number { return roundSwift(w * this.ch().windScale * 2) / 2; }

  private knockBack(victim: number): number | null {
    const ch = this.ch();
    const rng = new SplitMix64(hash64(this.state.seed, [u64(0, 0xB0B0), u64FromInt(this.state.turn)]));
    const offsets = this.state.conditions.archerOffsets;
    const old = offsets[victim];
    let push = rng.nextInt(ch.knockMin, ch.knockMax) / 10;
    push = Math.min(push, ch.maxKnockback - old);
    while (push >= 0.5) {
      offsets[victim] = old + push;
      if (this.windAllowsHits(this.state.windWorld) || this.windAllowsHits(0)) break;
      push -= 0.5;
    }
    if (push < 0.5) { offsets[victim] = old; return null; }
    this.state.windWorld = this.fittedWind(this.state.windWorld);
    return old + push;
  }

  private shiftWindAfterStrike(): number | null {
    const arena = arenaProfile(this.state.arena);
    const rng = new SplitMix64(hash64(this.state.seed, [u64(0, 0x5711CE), u64FromInt(this.state.turn)]));
    const w = this.state.windWorld;
    const sign = w < 0 ? -1 : (w > 0 ? 1 : this.windSign());
    const current = Math.abs(w);
    const lo = Math.trunc(roundSwift(arena.minWind * this.ch().windScale * 2));
    const hi = Math.trunc(roundSwift(arena.maxWind * this.ch().windScale * 2));
    const steps: number[] = [];
    for (let s = lo; s <= Math.max(lo, hi); s++) { if (s * 0.5 !== current) steps.push(s * 0.5); }
    if (steps.length === 0) return null;
    const next = this.fittedWind(sign * steps[rng.nextInt(0, steps.length - 1)]);
    if (next === this.state.windWorld) return null;
    this.state.windWorld = next;
    return next;
  }

  submit(angleTenthsRaw: number, powerPermilleRaw: number): TurnReport {
    if (this.state.phase.kind !== "awaitingShot") throw new Error("not awaiting a shot");
    const inp = clampInput(angleTenthsRaw, powerPermilleRaw);
    const st = this.state;
    const shooter = st.currentShooter;
    const target = 1 - shooter;
    const outcome = simulateShot(inp[0], inp[1], shooter, st.conditions);
    const hitArcher = outcome.impact === "archer" ? outcome.index! : null;

    let damage = 0;
    let damaged: number | null = null;
    if (hitArcher !== null) {
      damage = Math.floor(DAMAGE[outcome.part!] * 1);
      damaged = hitArcher;
      if (st.suddenDeath === 0) st.health[hitArcher] = Math.max(0, st.health[hitArcher] - damage);
      if (hitArcher === target) {
        st.hitsLanded[shooter] += 1;
        if (outcome.part === "head") st.headshots[shooter] += 1;
      }
    }
    const missDistance = hitArcher === target ? null : hitboxDistance({ x: outcome.x, y: outcome.y }, archerPosition(st.conditions, target));
    const nearMiss = missDistance !== null && missDistance <= NEAR_MISS_DISTANCE ? missDistance : null;

    const turn = st.turn;
    st.turn += 1;
    st.shotsThisRound[shooter] += 1;

    let events: TurnEvent[] = st.suddenDeath > 0
      ? this.resolveSuddenDeath(shooter, missDistance !== null ? missDistance : 0, hitArcher === target ? damage : 0)
      : this.resolveNormal(shooter);

    const hasNextTurn = events.some(function (e) { return e.indexOf("nextTurn:") === 0; });
    if (hitArcher !== null && st.suddenDeath === 0 && st.phase.kind === "awaitingShot" && hasNextTurn) {
      const w = this.shiftWindAfterStrike();
      if (w !== null) events.unshift("windChanged:" + f64Hex(w));
      const off = this.knockBack(hitArcher);
      if (off !== null) events.unshift("knockedBack:" + hitArcher + ":" + f64Hex(off));
    }
    this.syncWind();
    const last = events[events.length - 1];
    if (last && last.indexOf("roundOver:") === 0) {
      const winner = parseInt(last.split(":")[1], 10);
      st.roundsWon[winner] += 1;
      if (st.roundsWon[winner] >= st.roundsToWin) {
        st.phase = { kind: "matchOver", winner: winner };
        events.push("matchOver:" + winner);
      } else {
        st.phase = { kind: "roundOver", winner: winner };
      }
    }
    return { turn: turn, round: st.round, shooter: shooter, angleTenths: inp[0], powerPermille: inp[1], outcome: outcome,
             damagedArcher: damaged, damage: damage, health: [st.health[0], st.health[1]], missDistance: missDistance,
             nearMiss: nearMiss, events: events };
  }

  private resolveNormal(shooter: number): TurnEvent[] {
    const st = this.state;
    const first = st.roundFirstShooter, second = 1 - first;
    if (shooter === first) {
      st.currentShooter = second;
      st.lastBreath = st.health[second] === 0;
      return ["nextTurn:" + second + ":" + st.lastBreath];
    }
    st.lastBreath = false;
    const firstDown = st.health[first] === 0, secondDown = st.health[second] === 0;
    if (firstDown && secondDown) return this.startSuddenDeath();
    if (firstDown) return ["roundOver:" + second + ":knockout"];
    if (secondDown) return ["roundOver:" + first + ":knockout"];
    const limit = RULES.maxShotsPerPlayerPerRound;
    if (st.shotsThisRound[first] >= limit && st.shotsThisRound[second] >= limit) {
      if (st.health[first] === st.health[second]) return this.startSuddenDeath();
      const winner = st.health[first] > st.health[second] ? first : second;
      return ["roundOver:" + winner + ":turnLimit"];
    }
    st.currentShooter = first;
    st.pair += 1;
    return ["nextTurn:" + first + ":false"];
  }

  private startSuddenDeath(): TurnEvent[] {
    const st = this.state;
    st.suddenDeath += 1;
    st.suddenDeathShots = [null, null];
    st.lastBreath = false;
    st.conditions = generatePlayable(roundSeed(st.seed, st.round, st.suddenDeath), arenaProfile(st.arena));
    st.currentShooter = st.roundFirstShooter;
    st.windWorld = this.fittedWind(st.windWorld);
    this.syncWind();
    return ["suddenDeath:" + st.suddenDeath];
  }

  private resolveSuddenDeath(shooter: number, missDistance: number, damage: number): TurnEvent[] {
    const st = this.state;
    st.suddenDeathShots[shooter] = { missDistance: damage > 0 ? 0 : missDistance, damage: damage };
    const a = st.suddenDeathShots[0], b = st.suddenDeathShots[1];
    if (!a || !b) {
      st.currentShooter = 1 - shooter;
      return ["nextTurn:" + (1 - shooter) + ":false"];
    }
    let winner: number | null = null;
    if (a.damage > 0 || b.damage > 0) {
      if (a.damage !== b.damage) winner = a.damage > b.damage ? 0 : 1;
    } else if (a.missDistance !== b.missDistance) {
      winner = a.missDistance < b.missDistance ? 0 : 1;
    }
    if (winner !== null) return ["roundOver:" + winner + ":suddenDeath"];
    return this.startSuddenDeath();
  }

  startNextRound(): void {
    const st = this.state;
    if (st.phase.kind !== "roundOver") return;
    st.round += 1;
    st.roundFirstShooter = 1 - st.roundFirstShooter;
    st.currentShooter = st.roundFirstShooter;
    st.health = [RULES.startHealth, RULES.startHealth];
    st.shotsThisRound = [0, 0];
    st.lastBreath = false;
    st.suddenDeath = 0;
    st.suddenDeathShots = [null, null];
    st.pair = 0;
    st.conditions = generatePlayable(roundSeed(st.seed, st.round, 0), arenaProfile(st.arena));
    st.windWorld = this.fittedWind(st.windWorld);
    this.syncWind();
    st.phase = { kind: "awaitingShot" };
  }

  forfeit(player: number): void { this.state.phase = { kind: "matchOver", winner: 1 - player }; }

  /// Nakama hands match state back as plain data each tick, so the rules are
  /// re-attached to the saved state rather than kept as a live object.
  static wrap(state: MatchState): MatchEngine {
    const e: MatchEngine = Object.create(MatchEngine.prototype);
    e.state = state;
    return e;
  }
}
