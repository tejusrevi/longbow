// Longbow server runtime entry point (spec A22).

declare const nkruntime: any;

interface SimulateRequest { seed: string; arena: string; shooter: number; angleTenths: number; powerPermille: number }

function rpcPing(ctx: any, logger: any, nk: any, payload: string): string {
  return JSON.stringify({ ok: true, server: "longbow" });
}

/// Simulates one shot on fresh round conditions. Used to prove the server's
/// physics matches the app (golden vectors); not part of gameplay.
function rpcSimulateShots(ctx: any, logger: any, nk: any, payload: string): string {
  const reqs: SimulateRequest[] = JSON.parse(payload);
  const out: ShotOutcome[] = [];
  for (let i = 0; i < reqs.length; i++) {
    const r = reqs[i];
    const c = generateConditions(r.seed, arenaProfile(r.arena));
    out.push(simulateShot(r.angleTenths, r.powerPermille, r.shooter, c));
  }
  return JSON.stringify(out);
}

function InitModule(ctx: any, logger: any, nk: any, initializer: any): void {
  initializer.registerRpc("ping", rpcPing);
  initializer.registerRpc("simulate_shots", rpcSimulateShots);
  initializer.registerRpc("create_duel", rpcCreateDuel);
  initializer.registerRpc("join_duel", rpcJoinDuel);
  initializer.registerRpc("duel_history", rpcDuelHistory);
  initializer.registerMatch(DUEL_MODULE, {
    matchInit: duelInit, matchJoinAttempt: duelJoinAttempt, matchJoin: duelJoin, matchLeave: duelLeave,
    matchLoop: duelLoop, matchTerminate: duelTerminate, matchSignal: duelSignal,
  });
  logger.info("Longbow runtime loaded (physics v4, duels)");
}
