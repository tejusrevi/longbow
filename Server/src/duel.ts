// Friend duels (spec A7.2, A8): a 4-character code, two seats, the server
// holds the one true MatchEngine. Clients send only their inputs; the server
// simulates, then sends every result to both players.

const DUEL_MODULE = "duel";
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no O/0, I/1
const CODE_COLLECTION = "duel_codes";
const SYSTEM_USER = "00000000-0000-0000-0000-000000000000";

const OP = {
  // client → server
  SHOT: 1, READY: 2, LEAVE: 3,
  // server → client
  START: 10, RESULT: 11, END: 12, OPPONENT_AWAY: 13, OPPONENT_BACK: 14, REJECT: 15,
};

const TICK_RATE = 5;
const ANIMATION_ALLOWANCE_S = 16; // longest flight + reactions before the next shooter can aim
const ROUND_BREAK_S = 10;          // round banner and the opening pan of the next round
const AWAY_GRACE_S = 30;

interface Seat { userId: string; sessionId: string; name: string; avatar: any; hat: string; present: boolean; awaySince: number }

interface DuelState {
  code: string; challenge: string; seats: Array<Seat | null>; engine: MatchState | null; seedHex: string;
  deadlineTick: number; tick: number; endedTick: number; createdBy: string;
}

function randomHex64(): string {
  let s = "0x";
  for (let i = 0; i < 4; i++) s += ("0000" + Math.floor(Math.random() * 65536).toString(16)).slice(-4).toUpperCase();
  return s;
}

function newCode(): string {
  let c = "";
  for (let i = 0; i < 4; i++) c += CODE_ALPHABET.charAt(Math.floor(Math.random() * CODE_ALPHABET.length));
  return c;
}

function seatOf(s: DuelState, userId: string): number {
  for (let i = 0; i < 2; i++) { const st = s.seats[i]; if (st && st.userId === userId) return i; }
  return -1;
}

// --- RPCs -------------------------------------------------------------------

function rpcCreateDuel(ctx: any, logger: any, nk: any, payload: string): string {
  const req = payload ? JSON.parse(payload) : {};
  const challenge = CHALLENGES[req.challenge] ? req.challenge : "medium";
  for (let attempt = 0; attempt < 20; attempt++) {
    const code = newCode();
    const existing = nk.storageRead([{ collection: CODE_COLLECTION, key: code, userId: SYSTEM_USER }]);
    if (existing.length > 0) {
      // Codes are reused once their match is gone.
      const live = nk.matchGet(existing[0].value.matchId);
      if (live) continue;
    }
    const matchId = nk.matchCreate(DUEL_MODULE, { code: code, challenge: challenge, createdBy: ctx.userId });
    nk.storageWrite([{ collection: CODE_COLLECTION, key: code, userId: SYSTEM_USER, value: { matchId: matchId },
                       permissionRead: 0, permissionWrite: 0 }]);
    return JSON.stringify({ code: code, matchId: matchId });
  }
  throw new Error("could not allocate a duel code");
}

function rpcJoinDuel(ctx: any, logger: any, nk: any, payload: string): string {
  const req = JSON.parse(payload || "{}");
  const code = String(req.code || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  const found = nk.storageRead([{ collection: CODE_COLLECTION, key: code, userId: SYSTEM_USER }]);
  if (found.length === 0) return JSON.stringify({ error: "no_such_code" });
  const match = nk.matchGet(found[0].value.matchId);
  if (!match) return JSON.stringify({ error: "no_such_code" });
  const label = JSON.parse(match.label || "{}");
  if (!label.open && label.players && label.players.indexOf(ctx.userId) < 0) return JSON.stringify({ error: "full" });
  return JSON.stringify({ matchId: found[0].value.matchId });
}

// --- Match handler ----------------------------------------------------------

function label(s: DuelState): string {
  const players: string[] = [];
  for (let i = 0; i < 2; i++) { const st = s.seats[i]; if (st) players.push(st.userId); }
  return JSON.stringify({ code: s.code, open: players.length < 2 && s.engine === null, players: players });
}

function duelInit(ctx: any, logger: any, nk: any, params: any): { state: DuelState; tickRate: number; label: string } {
  const s: DuelState = { code: params.code, challenge: params.challenge || "medium", seats: [null, null], engine: null,
                         seedHex: "", deadlineTick: 0, tick: 0, endedTick: -1, createdBy: params.createdBy || "" };
  return { state: s, tickRate: TICK_RATE, label: label(s) };
}

function duelJoinAttempt(ctx: any, logger: any, nk: any, dispatcher: any, tick: number, s: DuelState, presence: any,
                         metadata: any): { state: DuelState; accept: boolean; rejectMessage?: string } {
  if (seatOf(s, presence.userId) >= 0) return { state: s, accept: true };
  if (s.engine !== null || (s.seats[0] && s.seats[1])) return { state: s, accept: false, rejectMessage: "full" };
  // The creator always takes the left seat.
  let seat = s.seats[0] ? 1 : 0;
  if (presence.userId !== s.createdBy && !s.seats[1] && seat === 0) seat = 1;
  s.seats[seat] = { userId: presence.userId, sessionId: presence.sessionId, name: String((metadata && metadata.name) || "PLAYER").slice(0, 16),
                    avatar: metadata && metadata.avatar ? JSON.parse(metadata.avatar) : null, hat: (metadata && metadata.hat) || "none",
                    present: false, awaySince: 0 };
  return { state: s, accept: true };
}

function broadcast(dispatcher: any, op: number, body: any, to?: any[]): void {
  dispatcher.broadcastMessage(op, JSON.stringify(body), to || null, null, true);
}

function startMessage(s: DuelState): any {
  const e = MatchEngine.wrap(s.engine!);
  return {
    seed: s.seedHex, arena: e.state.arena, roundsToWin: e.state.roundsToWin, challenge: s.challenge,
    firstShooter: tossWinner(u64FromHex(s.seedHex)), turn: e.state.turn,
    seats: s.seats.map(function (st) { return st ? { userId: st.userId, name: st.name, avatar: st.avatar, hat: st.hat } : null; }),
    history: (s as any).history || [],
  };
}

function duelJoin(ctx: any, logger: any, nk: any, dispatcher: any, tick: number, s: DuelState, presences: any[]): { state: DuelState } | null {
  for (let i = 0; i < presences.length; i++) {
    const seat = seatOf(s, presences[i].userId);
    if (seat < 0) continue;
    const st = s.seats[seat]!;
    st.present = true;
    st.sessionId = presences[i].sessionId;
    if (s.engine !== null) {
      // Rejoined: catch them up, and tell the other player they're back.
      broadcast(dispatcher, OP.START, startMessage(s), [presences[i]]);
      broadcast(dispatcher, OP.OPPONENT_BACK, { seat: seat });
    }
  }
  if (s.engine === null && s.seats[0] && s.seats[1] && s.seats[0].present && s.seats[1].present) {
    s.seedHex = randomHex64();
    s.engine = new MatchEngine(s.seedHex, "hills", RULES.roundsToWin, tossWinner(u64FromHex(s.seedHex)), s.challenge).state;
    (s as any).history = [];
    s.deadlineTick = tick + (RULES.shotTimeLimitSeconds + ANIMATION_ALLOWANCE_S) * TICK_RATE;
    broadcast(dispatcher, OP.START, startMessage(s));
    logger.info("duel %s started, seed %s", s.code, s.seedHex);
  }
  dispatcher.matchLabelUpdate(label(s));
  return { state: s };
}

function duelLeave(ctx: any, logger: any, nk: any, dispatcher: any, tick: number, s: DuelState, presences: any[]): { state: DuelState } | null {
  for (let i = 0; i < presences.length; i++) {
    const seat = seatOf(s, presences[i].userId);
    if (seat < 0) continue;
    const st = s.seats[seat]!;
    if (st.sessionId !== presences[i].sessionId) continue;
    st.present = false;
    st.awaySince = tick;
    if (s.engine === null) s.seats[seat] = null; // left the waiting room
    else if (s.endedTick < 0) broadcast(dispatcher, OP.OPPONENT_AWAY, { seat: seat, graceSeconds: AWAY_GRACE_S });
  }
  dispatcher.matchLabelUpdate(label(s));
  if (!s.seats[0] && !s.seats[1]) return null;
  return { state: s };
}

function playShot(s: DuelState, dispatcher: any, tick: number, angleTenths: number, powerPermille: number, timedOut: boolean): void {
  const e = MatchEngine.wrap(s.engine!);
  const r = e.submit(angleTenths, powerPermille);
  const msg = { turn: r.turn, shooter: r.shooter, angleTenths: r.angleTenths, powerPermille: r.powerPermille,
                health: r.health, events: r.events, timedOut: timedOut };
  (s as any).history.push(msg);
  broadcast(dispatcher, OP.RESULT, msg);
  const roundBreak = e.state.phase.kind === "roundOver";
  if (roundBreak) e.startNextRound();
  if (e.state.phase.kind === "matchOver") {
    broadcast(dispatcher, OP.END, { winner: e.state.phase.winner, reason: "won" });
    s.endedTick = tick;
  } else {
    s.deadlineTick = tick + (RULES.shotTimeLimitSeconds + ANIMATION_ALLOWANCE_S + (roundBreak ? ROUND_BREAK_S : 0)) * TICK_RATE;
  }
}

function duelLoop(ctx: any, logger: any, nk: any, dispatcher: any, tick: number, s: DuelState, messages: any[]): { state: DuelState } | null {
  s.tick = tick;
  if (s.endedTick >= 0) return tick - s.endedTick > 10 * TICK_RATE ? null : { state: s };
  // Nobody came: close an empty waiting room after ten minutes.
  if (s.engine === null) return tick > 600 * TICK_RATE ? null : { state: s };
  const e = MatchEngine.wrap(s.engine);

  for (let i = 0; i < messages.length; i++) {
    const m = messages[i];
    const seat = seatOf(s, m.sender.userId);
    if (seat < 0) continue;
    let body: any = {};
    try { body = JSON.parse(nk.binaryToString(m.data)); } catch (err) { continue; }
    if (m.opCode === OP.LEAVE) {
      e.forfeit(seat);
      broadcast(dispatcher, OP.END, { winner: 1 - seat, reason: "forfeit" });
      s.endedTick = tick;
      return { state: s };
    }
    if (m.opCode === OP.READY) {
      // The next shooter has finished watching: start their shot clock (plus a little grace).
      if (seat === e.state.currentShooter && body.turn === e.state.turn) s.deadlineTick = tick + (RULES.shotTimeLimitSeconds + 3) * TICK_RATE;
      continue;
    }
    if (m.opCode === OP.SHOT) {
      const a = body.angleTenths, p = body.powerPermille;
      const valid = e.state.phase.kind === "awaitingShot" && seat === e.state.currentShooter && body.turn === e.state.turn &&
        typeof a === "number" && typeof p === "number" && a % 1 === 0 && p % 1 === 0 &&
        a >= AIM.minAngleTenths && a <= AIM.maxAngleTenths && p >= 0 && p <= 1000;
      if (!valid) {
        logger.warn("duel %s rejected shot from seat %d for turn %d (expected %d)", s.code, seat, body.turn, e.state.turn);
        broadcast(dispatcher, OP.REJECT, { turn: body.turn, expectedTurn: e.state.turn }, [m.sender]);
        continue;
      }
      playShot(s, dispatcher, tick, a, p, false);
      if (s.endedTick >= 0) {
        logger.info("duel %s over after %d turns: seat %d won", s.code, e.state.turn - 1, (e.state.phase as any).winner);
        return { state: s };
      }
    }
  }

  // Someone gone too long forfeits.
  for (let i = 0; i < 2; i++) {
    const st = s.seats[i];
    if (st && !st.present && tick - st.awaySince > AWAY_GRACE_S * TICK_RATE) {
      e.forfeit(i);
      broadcast(dispatcher, OP.END, { winner: 1 - i, reason: "left" });
      s.endedTick = tick;
      return { state: s };
    }
  }
  // Shot clock ran out: the arrow drops at their feet (power 0, A6.11).
  if (tick > s.deadlineTick && e.state.phase.kind === "awaitingShot") {
    logger.info("duel %s: shot clock ran out for seat %d (turn %d)", s.code, e.state.currentShooter, e.state.turn);
    playShot(s, dispatcher, tick, 200, 0, true);
  }
  return { state: s };
}

function duelTerminate(ctx: any, logger: any, nk: any, dispatcher: any, tick: number, s: DuelState, grace: number): { state: DuelState } | null {
  return { state: s };
}

function duelSignal(ctx: any, logger: any, nk: any, dispatcher: any, tick: number, s: DuelState, data: string): { state: DuelState; data?: string } | null {
  if (data === "history" && s.engine) {
    const e = s.engine;
    return { state: s, data: JSON.stringify({ seed: s.seedHex, turn: e.turn, round: e.round, currentShooter: e.currentShooter,
      roundFirstShooter: e.roundFirstShooter, health: e.health, history: (s as any).history }) };
  }
  return { state: s, data: label(s) };
}

/// Debug: a duel's full official history, by code.
function rpcDuelHistory(ctx: any, logger: any, nk: any, payload: string): string {
  const code = JSON.parse(payload || "{}").code;
  const found = nk.storageRead([{ collection: CODE_COLLECTION, key: code, userId: SYSTEM_USER }]);
  if (found.length === 0) return JSON.stringify({ error: "no_such_code" });
  return nk.matchSignal(found[0].value.matchId, "history");
}
