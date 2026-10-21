// Deterministic shot simulation, a line-by-line port of LongbowCore's
// ShotSimulator, Terrain, RoundConditions.generate and hitboxes (spec A6.3).
// Every operation and its order match the Swift so results agree bit for bit;
// Shared/golden_shots.json proves it. Never call Math.sin/Math.cos here.

declare const TRIG_SIN: number[];
declare const TRIG_COS: number[];

interface Vec2 { x: number; y: number }
type HitShape = { kind: "circle"; c: Vec2; r: number } | { kind: "rect"; min: Vec2; max: Vec2 };
type BodyPart = "head" | "body" | "legs";

const PHYSICS = {
  minSpeed: 20, maxSpeed: 75, drag: 0.00015, gravity: 9.8, stepsPerSecond: 120, maxFlightSeconds: 18,
  boundsMarginX: 800, boundsBottom: -20, archerScale: 2.0, launchOffsetX: 0.35, launchOffsetY: 1.35,
};
const AIM = { minAngleTenths: -100, maxAngleTenths: 850 };

interface ArenaProfile {
  id: string; gravity: number | null; distanceMin: number; distanceMax: number; maxWind: number; minWind: number;
  waveAmplitudes: number[]; maxValleyDepth: number; obstacleKinds: string[]; maxObstacles: number;
}

const HILLS: ArenaProfile = {
  id: "hills", gravity: null, distanceMin: 150, distanceMax: 350, maxWind: 3, minWind: 0,
  waveAmplitudes: [7, 3, 1.2], maxValleyDepth: 12, obstacleKinds: ["tree", "rock"], maxObstacles: 2,
};

function arenaProfile(id: string): ArenaProfile {
  const p: ArenaProfile = JSON.parse(JSON.stringify(HILLS));
  p.id = id;
  if (id === "windmills") { p.minWind = 3; p.maxWind = 10; }
  if (id === "moon") { p.gravity = 1.6; p.minWind = 0; p.maxWind = 0; p.distanceMin = 300; p.distanceMax = 600; p.obstacleKinds = ["rock"]; }
  return p;
}

// --- Trig ---------------------------------------------------------------

function wrapTenths(t: number): number { const m = t % 3600; return m < 0 ? m + 3600 : m; }

function sinLerp(degrees: number): number {
  const t = degrees * 10.0;
  const f = Math.floor(t);
  const frac = t - f;
  const i = wrapTenths(f);
  const a = TRIG_SIN[i];
  const b = TRIG_SIN[i + 1];
  return a + (b - a) * frac;
}

// --- Terrain ------------------------------------------------------------

interface Wave { amplitude: number; wavelength: number; phaseDegrees: number }
interface Terrain { distance: number; waves: Wave[]; valleyDepth: number }

const PAD_HALF_WIDTH = 2.0, BLEND_WIDTH = 8.0, MIN_HEIGHT = -15.0;

function terrainRaw(t: Terrain, x: number): number {
  let sum = 0.0;
  for (let i = 0; i < t.waves.length; i++) {
    const w = t.waves[i];
    sum = sum + w.amplitude * sinLerp(w.phaseDegrees + 360.0 * x / w.wavelength);
  }
  return sum;
}

function terrainHeight(t: Terrain, x: number): number {
  const d = t.distance;
  const base = 0.5 * (terrainRaw(t, x) + terrainRaw(t, d - x)) - 0.5 * (terrainRaw(t, 0) + terrainRaw(t, d));
  const u = Math.min(Math.max(x / d, 0), 1);
  const valley = -t.valleyDepth * 4.0 * u * (1.0 - u);
  const edge = Math.min(Math.abs(x), Math.abs(x - d));
  let w = 0.0;
  if (edge > PAD_HALF_WIDTH) {
    const s = Math.min(1.0, (edge - PAD_HALF_WIDTH) / BLEND_WIDTH);
    w = s * s * (3.0 - 2.0 * s);
  }
  return Math.max(MIN_HEIGHT, w * (base + valley));
}

// --- Shapes -------------------------------------------------------------

function entry(shape: HitShape, p0: Vec2, p1: Vec2): number | null {
  if (shape.kind === "circle") {
    const dx = p1.x - p0.x, dy = p1.y - p0.y;
    const fx = p0.x - shape.c.x, fy = p0.y - shape.c.y;
    const cc = (fx * fx + fy * fy) - shape.r * shape.r;
    if (cc <= 0) return 0;
    const a = dx * dx + dy * dy;
    if (a === 0) return null;
    const b = 2 * (fx * dx + fy * dy);
    const disc = b * b - 4 * a * cc;
    if (disc < 0) return null;
    const t = (-b - Math.sqrt(disc)) / (2 * a);
    return (t >= 0 && t <= 1) ? t : null;
  }
  let t0 = 0.0, t1 = 1.0;
  const dx = p1.x - p0.x, dy = p1.y - p0.y;
  function clip(p: number, q: number): boolean {
    if (p === 0) return q >= 0;
    const r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
    return true;
  }
  if (!(clip(-dx, p0.x - shape.min.x) && clip(dx, shape.max.x - p0.x) &&
        clip(-dy, p0.y - shape.min.y) && clip(dy, shape.max.y - p0.y))) return null;
  return t0;
}

function offsetShape(s: HitShape, v: Vec2): HitShape {
  if (s.kind === "circle") return { kind: "circle", c: { x: s.c.x + v.x, y: s.c.y + v.y }, r: s.r };
  return { kind: "rect", min: { x: s.min.x + v.x, y: s.min.y + v.y }, max: { x: s.max.x + v.x, y: s.max.y + v.y } };
}

function hitboxes(feet: Vec2, s: number): Array<[BodyPart, HitShape]> {
  return [
    ["head", { kind: "circle", c: { x: feet.x, y: feet.y + 1.68 * s }, r: 0.33 * s }],
    ["body", { kind: "rect", min: { x: feet.x - 0.3 * s, y: feet.y + 0.85 * s }, max: { x: feet.x + 0.3 * s, y: feet.y + 1.5 * s } }],
    ["legs", { kind: "rect", min: { x: feet.x - 0.22 * s, y: feet.y }, max: { x: feet.x + 0.22 * s, y: feet.y + 0.85 * s } }],
  ];
}

interface Obstacle { kind: string; x: number; baseY: number; shapes: HitShape[] }

function makeObstacle(kind: string, x: number, baseY: number): Obstacle {
  const base = { x: x, y: baseY };
  let local: HitShape[];
  if (kind === "tree") {
    local = [{ kind: "circle", c: { x: 0, y: 5.6 }, r: 2.3 }, { kind: "rect", min: { x: -0.25, y: -0.5 }, max: { x: 0.25, y: 4.0 } }];
  } else if (kind === "rock") {
    local = [{ kind: "circle", c: { x: 0, y: 0.3 }, r: 1.1 }];
  } else {
    local = [{ kind: "rect", min: { x: -0.8, y: -0.5 }, max: { x: 0.8, y: 6 } }];
  }
  return { kind: kind, x: x, baseY: baseY, shapes: local.map(function (s) { return offsetShape(s, base); }) };
}

// --- Round conditions ---------------------------------------------------

interface RoundConditions {
  seedHex: string; arena: string; distance: number; windRelative: number; gravity: number;
  terrain: Terrain; obstacles: Obstacle[]; archerOffsets: number[];
}

function generateConditions(seedHex: string, arena: ArenaProfile): RoundConditions {
  const rng = new SplitMix64(u64FromHex(seedHex));
  const distance = rng.nextInt(arena.distanceMin, arena.distanceMax);
  const minSteps = Math.trunc(arena.minWind * 2);
  const maxSteps = Math.trunc(arena.maxWind * 2);
  const windStrength = rng.nextInt(minSteps, maxSteps) * 0.5;
  const windSign = rng.nextBool() ? 1 : -1;

  const waves: Wave[] = [];
  const ranges: Array<[number, number]> = [[distance * 0.5, distance * 1.1], [40, 90], [12, 28]];
  for (let i = 0; i < arena.waveAmplitudes.length; i++) {
    const range = ranges[Math.min(i, ranges.length - 1)];
    const amplitude = arena.waveAmplitudes[i] * rng.nextDouble(0.4, 1.0);
    const wavelength = rng.nextDouble(range[0], range[1]);
    const phaseDegrees = rng.nextInt(0, 359);
    waves.push({ amplitude: amplitude, wavelength: wavelength, phaseDegrees: phaseDegrees });
  }
  const valley = rng.nextDouble(0, arena.maxValleyDepth);
  const terrain: Terrain = { distance: distance, waves: waves, valleyDepth: valley };

  const obstacles: Obstacle[] = [];
  const count = arena.obstacleKinds.length === 0 ? 0 : rng.nextInt(0, arena.maxObstacles);
  if (count > 0) {
    const kind = arena.obstacleKinds[rng.nextInt(0, arena.obstacleKinds.length - 1)];
    if (count === 1) {
      const x = distance * 0.5;
      obstacles.push(makeObstacle(kind, x, terrainHeight(terrain, x)));
    } else {
      // Swift's .rounded() is half away from zero; x is positive, so Math.round matches.
      const x = Math.round(distance * rng.nextDouble(0.25, 0.42));
      obstacles.push(makeObstacle(kind, x, terrainHeight(terrain, x)));
      obstacles.push(makeObstacle(kind, distance - x, terrainHeight(terrain, distance - x)));
    }
  }
  return {
    seedHex: seedHex, arena: arena.id, distance: distance, windRelative: windStrength * windSign,
    gravity: arena.gravity !== null ? arena.gravity : PHYSICS.gravity, terrain: terrain, obstacles: obstacles,
    archerOffsets: [0, 0],
  };
}

function facing(index: number): number { return index === 0 ? 1 : -1; }

function archerPosition(c: RoundConditions, index: number): Vec2 {
  const x = index === 0 ? -c.archerOffsets[0] : c.distance + c.archerOffsets[1];
  return { x: x, y: c.archerOffsets[index] === 0 ? 0 : terrainHeight(c.terrain, x) };
}

// --- Simulation ---------------------------------------------------------

interface ShotOutcome {
  impact: "archer" | "terrain" | "obstacle" | "outOfBounds" | "timeout";
  index?: number; part?: BodyPart; x: number; y: number; vx: number; vy: number; steps: number;
}

function clampInput(angleTenths: number, powerPermille: number): [number, number] {
  return [Math.min(Math.max(angleTenths, AIM.minAngleTenths), AIM.maxAngleTenths), Math.min(Math.max(powerPermille, 0), 1000)];
}

function simulateShot(angleTenthsRaw: number, powerPermilleRaw: number, shooter: number, c: RoundConditions): ShotOutcome {
  const inp = clampInput(angleTenthsRaw, powerPermilleRaw);
  const angleTenths = inp[0];
  const power = inp[1] / 1000;
  const dir = facing(shooter);
  const dt = 1.0 / PHYSICS.stepsPerSecond;
  const maxSteps = Math.trunc(PHYSICS.maxFlightSeconds * PHYSICS.stepsPerSecond);

  const v0 = PHYSICS.minSpeed + power * (PHYSICS.maxSpeed - PHYSICS.minSpeed);
  let vx = dir * (v0 * TRIG_COS[wrapTenths(angleTenths)]);
  let vy = v0 * TRIG_SIN[wrapTenths(angleTenths)];
  const windAx = dir * c.windRelative;
  const drag = PHYSICS.drag;
  const g = c.gravity;

  const feet = archerPosition(c, shooter);
  const scale = PHYSICS.archerScale;
  let px = feet.x + dir * (PHYSICS.launchOffsetX * scale);
  let py = feet.y + PHYSICS.launchOffsetY * scale;

  const target = 1 - shooter;
  const archers: Array<[number, Array<[BodyPart, HitShape]>]> = [
    [target, hitboxes(archerPosition(c, target), scale)],
    [shooter, hitboxes(feet, scale)],
  ];
  const minX = -PHYSICS.boundsMarginX;
  const maxX = c.distance + PHYSICS.boundsMarginX;
  const minY = PHYSICS.boundsBottom;

  let step = 0;
  while (step < maxSteps) {
    step += 1;
    const speed = Math.sqrt(vx * vx + vy * vy);
    const ax = windAx - drag * vx * speed;
    const ay = -g - drag * vy * speed;
    vx = vx + ax * dt;
    vy = vy + ay * dt;
    const prev = { x: px, y: py };
    px = prev.x + vx * dt;
    py = prev.y + vy * dt;
    const pos = { x: px, y: py };

    for (let a = 0; a < archers.length; a++) {
      const shapes = archers[a][1];
      for (let s = 0; s < shapes.length; s++) {
        const t = entry(shapes[s][1], prev, pos);
        if (t !== null) {
          return { impact: "archer", index: archers[a][0], part: shapes[s][0],
                   x: prev.x + (pos.x - prev.x) * t, y: prev.y + (pos.y - prev.y) * t, vx: vx, vy: vy, steps: step };
        }
      }
    }
    for (let o = 0; o < c.obstacles.length; o++) {
      const shapes = c.obstacles[o].shapes;
      for (let s = 0; s < shapes.length; s++) {
        const t = entry(shapes[s], prev, pos);
        if (t !== null) {
          return { impact: "obstacle", index: o,
                   x: prev.x + (pos.x - prev.x) * t, y: prev.y + (pos.y - prev.y) * t, vx: vx, vy: vy, steps: step };
        }
      }
    }
    if (pos.y <= terrainHeight(c.terrain, pos.x)) {
      let lo = 0.0, hi = 1.0;
      for (let k = 0; k < 12; k++) {
        const mid = (lo + hi) * 0.5;
        const qx = prev.x + (pos.x - prev.x) * mid, qy = prev.y + (pos.y - prev.y) * mid;
        if (qy <= terrainHeight(c.terrain, qx)) hi = mid; else lo = mid;
      }
      return { impact: "terrain", x: prev.x + (pos.x - prev.x) * hi, y: prev.y + (pos.y - prev.y) * hi, vx: vx, vy: vy, steps: step };
    }
    if (pos.x < minX || pos.x > maxX || pos.y < minY) {
      return { impact: "outOfBounds", x: pos.x, y: pos.y, vx: vx, vy: vy, steps: step };
    }
  }
  return { impact: "timeout", x: px, y: py, vx: vx, vy: vy, steps: step };
}
