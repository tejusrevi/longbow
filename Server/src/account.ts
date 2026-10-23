// Player identity (spec A7.1): gamertag, country, and deleting the account.
// The gamertag is the Nakama username, stored lowercase so "Tej" and "tej"
// can't both exist; display_name keeps the player's own casing. Country is
// an ISO 3166 alpha-2 code in the account's location field.

const GAMERTAG_PATTERN = /^[A-Za-z0-9_]{3,16}$/;
// A short list of words no gamertag may contain. Not exhaustive: it stops the
// obvious, and the console can rename anything that slips through.
const BLOCKED_WORDS = ["fuck", "shit", "cunt", "nigg", "fag", "rape", "nazi", "hitler", "slut", "whore", "porn", "dick", "cock", "pussy", "bitch"];

interface Profile { gamertag: string | null; country: string | null }

function gamertagProblem(tag: string): string | null {
  if (!GAMERTAG_PATTERN.test(tag)) return "invalid";
  const plain = tag.toLowerCase().replace(/_/g, "").replace(/0/g, "o").replace(/1/g, "i").replace(/3/g, "e").replace(/4/g, "a").replace(/5/g, "s");
  for (let i = 0; i < BLOCKED_WORDS.length; i++) if (plain.indexOf(BLOCKED_WORDS[i]) >= 0) return "not_allowed";
  return null;
}

/// The profile as other players see it. A gamertag counts only once the
/// player picked one (Nakama makes up a random username on sign-up).
function profileOf(nk: any, userId: string): Profile {
  const account = nk.accountGetId(userId);
  const user = account.user || {};
  const meta = user.metadata || {};
  return { gamertag: meta.gamertagSet ? (user.displayName || user.username) : null, country: user.location || null };
}

function rpcGetProfile(ctx: any, logger: any, nk: any, payload: string): string {
  return JSON.stringify(profileOf(nk, ctx.userId));
}

function rpcSetProfile(ctx: any, logger: any, nk: any, payload: string): string {
  const req = JSON.parse(payload || "{}");
  const tag = String(req.gamertag || "").trim();
  const country = String(req.country || "").toUpperCase();
  const problem = gamertagProblem(tag);
  if (problem) return JSON.stringify({ error: problem });
  if (!/^[A-Z]{2}$/.test(country)) return JSON.stringify({ error: "bad_country" });
  const current = nk.accountGetId(ctx.userId).user || {};
  const meta = current.metadata || {};
  meta.gamertagSet = true;
  try {
    // Arguments: userId, username, displayName, timezone, location, langTag, avatarUrl, metadata.
    nk.accountUpdateId(ctx.userId, tag.toLowerCase(), tag, null, country, null, null, meta);
  } catch (err) {
    const msg = String((err as any) && ((err as any).message || err));
    if (/username/i.test(msg) && /(use|exists|taken|unique)/i.test(msg)) return JSON.stringify({ error: "taken" });
    logger.error("set_profile failed: %s", msg);
    throw err;
  }
  return JSON.stringify({ gamertag: tag, country: country });
}

/// Deletes the player's account and everything stored under it. The app
/// then forgets its device id, so the next launch starts a fresh account.
function rpcDeleteAccount(ctx: any, logger: any, nk: any, payload: string): string {
  if (!ctx.userId) throw new Error("not signed in");
  nk.accountDeleteId(ctx.userId, false);
  logger.info("account %s deleted at the player's request", ctx.userId);
  return JSON.stringify({ deleted: true });
}
