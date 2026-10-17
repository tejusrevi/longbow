# Longbow — Product & Technical Specification

> Working title: **Longbow**. The final name is not decided. Keep the display name in one constant (`AppInfo.displayName`) and never hard-code it elsewhere.
>
> **Audience:** this document is the build brief for Claude Code. It describes every feature down to the details. Where a number is given (physics, timers, points), treat it as a **starting value to tune**, and put it in remote config, never as a literal in game code.
>
> **Monetization is OFF for the first release.** Everything about money lives in Part B and is behind feature flags. Part A must build, ship and run with no monetization code paths active.

---

## How to read this document

- **Part A** — the game: everything that ships in v1.0 and later, with no money involved.
- **Part B** — monetization: designed now, built behind flags, switched on later without an app update where possible.
- Every feature carries a release tag:
  - **[v1.0]** — first public release (soft launch in Canada, then global).
  - **[v1.1]** — first update after soft launch.
  - **[Later]** — planned, not scheduled.
  - **[Flag: …]** — controlled by the named feature flag (Section A23).
- The visual mockups live on the design canvas ("Longbow — Game Mockups"). Screen names below match the canvas artboards (for example `Aim.dc.html`).

---

# PART A — THE GAME

## A1. Concept

A minimalist, turn-based archery duel for iPhone, inspired by the classic web game *Bowman 2*. Two hand-drawn archers stand on opposite hills. Players take turns: drag back to draw the bow, release to shoot. The camera follows the arrow to its target. First archer to lose all health loses the round.

**Pillars**
1. **One gesture.** Drag back, let go. Nothing else is needed to play.
2. **One more try.** The ghost of your last shot, visible near misses and short matches make every miss a reason to shoot again.
3. **Fair.** Both players always shoot under the same conditions and get the same number of shots.
4. **Quiet design.** Dieter Rams principles: as little UI as possible, nothing on screen that isn't needed right now.

## A2. Platform & technical baseline

| Item | Decision |
| --- | --- |
| Platform | iOS only (iPhone). iPad runs the iPhone layout scaled — no separate iPad layout in v1.0. |
| Minimum iOS | iOS 17 |
| Orientation | Landscape only (left and right). Lock in Info.plist. |
| Language | Swift 5.9+ |
| Game rendering | SpriteKit (`SKScene`, `SKCameraNode`, `SKShader` for halftone) |
| Menus and screens | SwiftUI, hosting the SpriteKit scene via `SpriteView` |
| Physics | Custom deterministic projectile simulation (Section A6). Do **not** use SpriteKit physics bodies for arrow flight or hits. |
| Backend | Nakama (open-source game server), managed hosting. Server runtime code in TypeScript. |
| Accounts | Game Center (silent sign-in) + device account + optional Sign in with Apple |
| Push | Apple Push Notification service via the backend |
| Persistence on device | Keychain (device account token), `UserDefaults` (settings), local cache files (cosmetics, last state) |
| Analytics | Behind an `AnalyticsService` protocol. Provider chosen later; v1.0 may log to the backend. |
| Frame rate | 60 fps target; ProMotion 120 fps where supported for menus and flight |

## A3. Architecture

Organise the code in these modules (Swift packages or folders). Each service is a **protocol with a concrete implementation**, so implementations can be swapped (Game Center → own server, no ads → ads) without touching game code.

```
LongbowApp/            App entry, routing, dependency container
Core/                  Pure Swift, no UIKit/SpriteKit. Deterministic and unit-tested.
  Physics/             Shot simulation, collision, hitboxes
  Rules/               Match, round, turn, damage, scoring rules
  Random/              Seeded RNG (shared algorithm with server)
  Models/              Player, Match, Round, Shot, Arena, Cosmetic, LeagueEntry
Game/                  SpriteKit scenes, nodes, camera, effects, line boil, halftone
UI/                    SwiftUI screens and components
Services/
  AuthService          Device account, Game Center, Sign in with Apple
  MatchService         Create/join/play matches (live + async), server-backed
  LeaderboardService   Weekly league, friends, global
  ProfileService       Gamertag, country, cosmetics, XP, feathers
  DailyShotService     Daily challenge
  NotificationService  Push registration and handling
  AnalyticsService     Event logging (Section A21)
  RemoteConfigService  Fetches config + feature flags at launch (Section A23)
  AudioService / HapticsService
  MonetizationService  PART B. v1.0 ships the NoOp implementation only.
Server/                Nakama TypeScript runtime: RPCs, match handler, physics port, cron jobs
Shared/                Golden test vectors (JSON) used by BOTH client and server tests
AppClip/               [v1.1] App Clip target
```

**Rules for Claude Code**
- `Core` must have no dependency on UI, SpriteKit, network or monetization.
- Game code never calls a concrete service — only its protocol, injected from the dependency container.
- All tunable numbers come from `RemoteConfigService`, with bundled defaults in `DefaultConfig.json`.

## A4. Visual design system

### Colour
| Token | Value | Use |
| --- | --- | --- |
| `paper` | `#F3F0E8` | Background everywhere |
| `ink` | `#111111` | All lines, text, fills |
| `inkQuiet` | `#555555` | Secondary text (must still meet 4.5:1 contrast on paper) |
| `flag colours` | Real flag colours | **Only** inside country flags (leaderboard, profile, settings) |
| `premiumAccent` | `#C8102E` (red) | **PART B only.** Reserved for premium cosmetics. Not rendered anywhere in v1.0. |

Rule: the game is black and white. The only colour allowed in v1.0 is flags.

### Type
| Role | Font | Notes |
| --- | --- | --- |
| Display / buttons | Archivo Black | Wordmark, big moments (HEADSHOT), button labels |
| Data / labels | Space Mono (400, 700) | Numbers, scores, labels, settings text |
| Hand notes | Shantell Sans (500, 700) | Short hand-written hints only ("so close.", "top 5 move up") |

All three are open-licence Google Fonts — bundle them in the app.

### Illustration style
- Hand-drawn caricatures, thick black outlines, round caps and joins, slightly wobbly ("curly natural") lines.
- Shading only with **halftone dots** — never grey fills or gradients.
- Characters drawn as separate parts so they can animate: head, body, legs, back arm, front arm, bow, string, arrow, hat slot.
- **Line boil:** every drawn element has 3 slightly different hand-drawn versions, cycled at 8 fps, so drawings feel alive when still. Toggle in remote config.
- **Halftone shader:** an `SKShader` that converts greyscale artwork into a dot pattern. Dot size and angle configurable. Artists can paint in grey and get halftone automatically.

### Characters
- **Bjorn** — default player character: visor helmet, big halftone beard, black t-shirt, halftone trousers.
- **Gus** — default opponent/AI: black hood, big moustache, halftone t-shirt, black trousers.
- Online opponents appear as their own character with their equipped hat.
- **Every player's archer wears their own avatar face** (Section A14a). Bjorn and Gus are the default faces for new players and the AI; once a player customises their face, their archer's head uses it everywhere.
- Expressions: neutral, focused (aiming), hit (spiral eyes, open mouth), relieved (sweat drops), victorious, defeated.

### UI components
- Pill buttons: primary = black fill / paper text, 60–64 pt high; secondary = 3 pt black outline.
- Icon buttons: 44–48 pt square with 12 pt radius, or circle; always an accessibility label.
- Health bar: thin hand-drawn outline, black fill; lost health shown as halftone dots.
- Hand-drawn four-point sparkle stars as decoration on key moments.
- Minimum touch target: 44 × 44 pt.

## A5. Screen list and navigation

| # | Screen | Canvas artboard | Tag |
| --- | --- | --- | --- |
| 1 | Launch / splash (wordmark only, < 1 s) | — | [v1.0] |
| 2 | Pick your name (account creation) | `Gamertag.dc.html` | [v1.0] |
| 3 | Title / home | `Main.dc.html` | [v1.0] |
| 4 | Mode select: vs AI difficulty | — (simple sheet) | [v1.0] |
| 5 | Toss | `Toss.dc.html` | [v1.0] |
| 6 | Aim | `Aim.dc.html` | [v1.0] |
| 7 | Flight | `Flight.dc.html` | [v1.0] |
| 8 | Hit | `Hit.dc.html` | [v1.0] |
| 9 | Near miss | `Miss.dc.html` | [v1.0] |
| 10 | Their turn — brace | `Incoming.dc.html` | [v1.0] |
| 11 | Round result (between rounds) | — | [v1.0] |
| 12 | Match result | `Results.dc.html` | [v1.0] |
| 13 | Online (friend / quick match) | `Online.dc.html` | [v1.0] |
| 14 | Arenas | `Arenas.dc.html` | [v1.0] |
| 15 | Hats (wardrobe) | `Wardrobe.dc.html` | [v1.0] |
| 16 | Settings | `Settings.dc.html` | [v1.0] |
| 17 | Country picker | `Country.dc.html` | [v1.0] |
| 18 | Weekly leaderboard | `Leaderboard.dc.html` | [v1.0] |
| 19 | Daily Shot | — (to be mocked up) | [v1.0] |
| 20 | Matches in progress (async inbox) | — (to be mocked up) | [v1.0] |
| 21 | Profile (own and other players) | — | [v1.0] |
| 22 | Avatar editor (faces) | — (to be mocked up) | [v1.0] |
| 23 | Practice range | — | [v1.1] |
| 24 | Ranked ladder | — | [v1.1] |
| 25 | App Clip turn | — | [v1.1] |
| 26 | Shop | — | PART B |
| 27 | Season pass track | — | PART B |

**Home screen layout** (`Main.dc.html`): wordmark top-left with hand-drawn underline. Buttons: **PLAY** (primary, goes to vs AI) and **ONLINE** (secondary). [v1.0] add a **DAILY SHOT** entry with a countdown to the next one, and a small **inbox badge** when an async match is waiting for your turn. Top-right: settings icon button, profile button (black circle with smiling face → Hats). Right half: scene with Bjorn on a hill, Gus far away on another, dotted arc between them, sparkles.

**Navigation rules**
- Back is always a top-left 48 pt square button with a chevron.
- In a match there is only a pause button (bottom-left during your aim). Pause menu: Resume, Sound on/off, Forfeit (with confirmation).
- No tab bar. Home is the hub.

## A6. Core gameplay

### A6.1 Units and world
- World units are **metres**. Origin at the left player's feet; x to the right, y up.
- Distance between archers: **150–350 m** per round (from the round seed).
- Archers stand on hill tops; terrain is a height function generated from the seed (Section A6.7).

### A6.2 Input — aiming
- The player touches **anywhere** on the screen during their turn and drags.
- The drag vector, **pointing backwards from the touch-down point**, sets the shot:
  - **Angle** = direction opposite to the drag, clamped to **−10° … 85°** (relative to horizontal, facing the opponent).
  - **Power** = drag length / `maxDragLength` (remote config, default **40 % of screen height**), clamped 0…1.
- Quantise before simulation: angle to **0.1°**, power to **0.1 %** (integers `angleTenths`, `powerPermille`). The quantised values are what is simulated and sent to the server.
- Release to shoot. Dragging back inside a **12 pt dead zone** around the touch-down point cancels the shot.
- During the drag:
  - Archer's bow arm rotates to the angle; string visibly pulls back proportionally to power.
  - Angle shown as large text near the archer (for example `38°`).
  - Power shown as a ring filling around the finger (no number).
  - A short dotted aim guide shows the **first 15 %** of the trajectory only (remote config; 0 = off for hard modes).
  - Haptic tick every 5 % of power.
- **Ghost of last shot:** your previous shot's full path is drawn as a faint dotted line with an × where it landed. Shown only for your own last shot in the current round.

### A6.3 Shot physics (deterministic)
Simulate in `Core/Physics` with a **fixed timestep of 1/120 s**, using `Double`.

```
v0          = minSpeed + power * (maxSpeed - minSpeed)       // defaults 20 and 75 m/s
vx, vy      = v0 * cosTable[angleTenths], v0 * sinTable[angleTenths]
each step:
  ax = wind.acceleration - drag * vx * |v|                   // wind in m/s², drag default 0.0008
  ay = -gravity - drag * vy * |v|                            // gravity default 9.8 (arena may override)
  vx += ax * dt;  vy += ay * dt
  x  += vx * dt;  y  += vy * dt
  arrow angle = atan2(vy, vx)   // visual only, not used for collision
stop when: hits a hitbox, hits terrain, hits an obstacle, or leaves the world bounds (x < -50 or x > distance + 50, or y < -20)
max flight time: 12 s (safety)
```

**Determinism rules (critical — client and server must agree bit for bit):**
- Use **lookup tables** for sin and cos, indexed by `angleTenths` (0…3600), generated once and shipped as a data file in `Shared/` for both client and server. Never call `sin`/`cos` on the hot path.
- No other transcendental functions in the simulation (`atan2` above is visual only).
- Only basic arithmetic in a fixed order. No `Float`, no fused multiply-add assumptions, no parallelism.
- `Shared/golden_shots.json`: at least 500 shots (inputs + seed → exact result). Client unit tests and server tests must both pass all of them. CI fails on any mismatch.

### A6.4 Hitboxes and damage
Per archer, in metres relative to the feet:

| Part | Shape | Damage (default) |
| --- | --- | --- |
| Head | Circle, radius 0.22 m, centre at 1.62 m | **50** — "HEADSHOT" |
| Body | Rectangle 0.5 × 0.7 m, bottom at 0.85 m | **25** |
| Legs | Rectangle 0.4 × 0.85 m, bottom at 0 m | **15** |

- Collision is tested **segment vs shape** for each simulation step (from previous to current position), so fast arrows never tunnel through.
- The first shape hit wins; head is checked before body before legs.
- Health per archer per round: **100**.
- The arrow **stays stuck** in the character where it hit, at its angle, for the rest of the round (cap: 12 visible arrows per archer; oldest removed).
- Arrows that hit terrain stay stuck in the ground for the rest of the round (cap 20).

### A6.5 Match structure
- A **match** is played in **rounds**. First to win **3 rounds** wins the match (remote config: `roundsToWin`, default 3; vs AI Easy uses 2).
- A **round**: both archers start with 100 health. Players alternate single shots until one reaches 0.
- **Equal shots rule (fairness):** turns come in pairs. If the first shooter of a pair brings the opponent to 0, the opponent still takes their reply shot (a "last breath" shot, labelled on screen). If that reply also brings the first shooter to 0, the round is a **draw** and goes to **sudden death**: one shot each with fresh conditions, closest to a hit wins (if both hit, higher damage wins; if equal, another sudden-death pair).
- **Who shoots first:** decided by the toss in round 1; alternates every round after.
- **Turn limit per round:** 20 shots each (safety). If reached, the archer with more health wins the round; equal health → sudden death.

### A6.6 Conditions per round (mirrored fairness)
Generated from `roundSeed = hash(matchSeed, roundNumber)`:
- **Distance:** 150–350 m.
- **Wind:** strength 0–6 m/s² (rounded to 0.5), shown as a flag icon with a number. Wind is **mirrored per shooter**: each player experiences the same wind relative to their own shooting direction (both get a headwind of 4, or both get a tailwind of 4). Wind stays constant for the whole round.
- **Terrain:** the map is **mirror-symmetric** about the midpoint in ranked and leaderboard-counting matches. Casual matches may use asymmetric maps ([v1.1], remote config `allowAsymmetricMaps`).
- **Obstacles:** 0–2 per round (tree, rock, wall), also mirror-placed, from the arena's obstacle set.

Conditions **never** change between the two players' shots within a round.

### A6.7 Terrain generation
- Terrain = sum of 3 sine-like curves from a **lookup-based noise** (no transcendental calls; use precomputed tables) with amplitudes from the arena profile.
- Both archers stand on a flattened area 4 m wide at their x position.
- Height difference between the two archers: ±0–25 m.
- Visual: hand-drawn hill outline, halftone dots below the ground line, grass tufts, occasional stones.

### A6.8 Camera
Three states, driven by `GameCameraController` (`SKCameraNode`):
1. **Shooter view** (aiming): shooter at roughly 20 % from the left (or right, if they face left), zoom showing ~60 m of world width so the archer is about 25 % of screen height. Opponent off-screen; edge indicator shows their distance (`214 ▸`).
2. **Follow:** after release, the camera follows the arrow with smoothing (critical damping, 0.25 s), leading slightly ahead of the arrow in its travel direction. Zoom eases out to ~120 m of world width at peak height. A thin **mini-map** at the top shows both archers and the arrow's position on the arc.
3. **Impact:** camera eases to the impact point, frames the target archer, holds 1.2 s for the hit or near-miss moment, then pans to the next shooter (0.8 s).
- **Hold to slow time** during flight: hourglass button bottom-right; while held, simulation playback runs at 0.3× (visual only — the result is already computed).
- Screen shake on headshots (6 pt, 0.25 s), respecting Reduce Motion.
- Opening shot of each round: a quick 1.5 s pan from the opponent to the shooter, showing the whole field once.

### A6.9 Moments and feedback
| Moment | What happens |
| --- | --- |
| **Toss** (`Toss.dc.html`) | Arrow spins on a stump between two portraits, slows, points at the first shooter. Caption: "you shoot first" / "Gus shoots first". Tap to skip. |
| **Hit** (`Hit.dc.html`) | Zoom on the target, halftone burst behind them, character reaction, damage sticker (`−50`), big word for headshots only ("HEADSHOT"). Health bar animates down; lost health turns into dots. |
| **Near miss** (`Miss.dc.html`) | If an arrow lands within **3 m** of the target without hitting, show a hand-drawn measuring line and the distance (`1.8 m`), target sweats with relief, hand-note "so close.". |
| **Plain miss** | Arrow sticks in ground or flies off; no text, camera returns. |
| **Last breath** | When the reply shot under the equal-shots rule is coming, a small label "last breath" appears under the shooter. |
| **Round won/lost** | Short overlay with the round score (`2–1`) and the next round starting. |
| **Match result** (`Results.dc.html`) | Score (`3–1`), opponent portrait with every landed arrow stuck in it, XP bar with gain, buttons REMATCH, Home, Share. |

### A6.10 Brace (defensive timing)
- When the opponent's arrow is flying at you **in live play (vs AI, live online)**, a BRACE button with a shrinking timing ring appears bottom-right (`Incoming.dc.html`).
- Tap when the ring meets the target circle:
  - **Perfect** (±60 ms): damage × 0.5
  - **Good** (±150 ms): damage × 0.75
  - Miss or no tap: full damage
- **Once per round** per player.
- **Not available in async matches** (the defender is not watching live) and **not in the Daily Shot**.
- Brace is part of the shot result the server computes: in live matches the client sends the brace tap time; the server validates it against the flight time.
- Remote config `braceEnabled` (default on).

### A6.11 Timers
| Situation | Limit | When it runs out |
| --- | --- | --- |
| Live match — your shot | 20 s (a ring around the pause button shows time left from 5 s) | Auto-shot with power 0 (the arrow drops in front of you) |
| Async match — your turn | 24 h | Reminder push at 20 h; at 48 h without a shot the match is forfeited |
| Live match — opponent disconnected | 30 s reconnect window | Opponent forfeits the match |

## A7. Game modes

### A7.1 Play vs AI [v1.0]
- Opponent: Gus (and later other AI characters).
- Difficulties: **Easy, Medium, Hard**; [v1.1] **Gus the Legend** (unlocks after beating Hard 3 times).
- **AI algorithm:**
  1. Simulate candidate shots across angles (step 2°) and powers (step 2 %) with the real physics, using the current conditions.
  2. Pick the best shot (aim for head on Hard, body otherwise).
  3. Add aiming error: angle noise and power noise drawn from a normal distribution — Easy σ = 6° / 8 %, Medium σ = 3° / 4 %, Hard σ = 1.2° / 1.5 %.
  4. **Learning:** after each miss the AI reduces its error by 30 % for the next shot in the round (mimics a human correcting).
  5. Think time 1.2–2.5 s, with a drawing animation.
  6. AI brace: Easy never, Medium 40 % "good", Hard 70 % "good" / 20 % "perfect".
- vs AI matches run fully on the device (no server). Results count for XP and hat unlocks, not for the leaderboard.
- Works offline.

### A7.2 Friend duel [v1.0]
- From Online → **FRIEND**: creates a match with a **4-character code** (letters and digits, excluding look-alikes O/0, I/1) and an invite link.
- Share via the iOS share sheet. The link opens the app (Universal Link) or the App Store if not installed ([v1.1]: opens the App Clip).
- "Have a code?" field to join by typing the code.
- Choice of pace when creating (segmented control, `Online.dc.html`):
  - **LIVE** — both play now, 20 s per shot.
  - **1 SHOT / DAY** (async) — 24 h per turn, push notification on your turn.
- Friend duels count for XP and leaderboard points (Section A11) only if both players have a gamertag.

### A7.3 Quick match [v1.0]
- From Online → **ANYONE**: live matchmaking with a random player of similar skill (hidden rating, Section A11.4).
- Search screen: spinner illustration, timer (`0:07`), cancel button.
- Widening search: ±100 rating for 10 s, ±250 until 30 s, then anyone. After 45 s offer "Play Gus instead?".
- Region: prefer the same region for latency, widen after 20 s.

### A7.4 Daily Shot [v1.0]
- One shot per day, the **same conditions for every player in the world** (seed = date in UTC).
- Target: a stationary straw dummy at the day's distance.
- Score 0–1000: headshot centre = 1000, falling off with distance from the head centre; body and legs score less; miss scores by closeness (up to 200).
- One counted attempt. After it: your score, your rank today (global and in your country), and buttons **Play a match** and **Practice this shot** (practice is unlimited and never counts).
- Daily Shot score feeds weekly league points (Section A11.2).
- New Daily Shot at **00:00 UTC**; home screen shows a countdown.
- Streak: consecutive days played, shown on the Daily Shot screen. [Flag: monetization — streak protection is Part B.]

### A7.5 Practice range [v1.1]
- Free shooting at targets at chosen distances and wind. No opponent, no timer, no rewards.

### A7.6 Ranked [v1.1]
- Separate ranked queue with a visible rank and monthly seasons.
- **Ranked is pure skill:** no boosts, no purchases, no ads, no consumables affect it. (Part B must respect this.)
- Mirrored maps only.

## A8. Online multiplayer — technical

### A8.1 Authority
- The **server is authoritative** for every online match and for the Daily Shot.
- The client sends **inputs only** (`angleTenths`, `powerPermille`, optional `braceOffsetMs`). The server simulates the shot with the same physics code (TypeScript port + golden vectors) and returns the result.
- The client plays its own local simulation immediately for responsiveness; on receiving the server result it **reconciles** — if the impact differs (should never happen if determinism holds), it snaps to the server result at impact and logs an analytics error.

### A8.2 Messages
Shot submission (client → server):
```json
{ "matchId": "m_8f2c", "round": 2, "turn": 7, "angleTenths": 382, "powerPermille": 780, "braceOffsetMs": null, "clientVersion": "1.0.0" }
```
Shot result (server → both clients):
```json
{
  "matchId": "m_8f2c", "round": 2, "turn": 7, "shooter": "p_bjorn",
  "angleTenths": 382, "powerPermille": 780,
  "result": { "hit": "head", "damage": 50, "braced": "none", "impact": [212.4, 1.71], "flightMs": 4120 },
  "health": { "p_bjorn": 100, "p_gus": 50 },
  "next": { "shooter": "p_gus", "turn": 8, "deadline": "2026-10-17T21:05:00Z" }
}
```
- `turn` numbers are strictly increasing; the server rejects a turn that is not the current one, and clients ignore results with an old turn number.
- Round start message carries the round seed, distance, wind and terrain id so both clients render identical conditions.

### A8.3 Match state machine (server)
`waiting_for_opponent → toss → round_start → awaiting_shot(player) → resolving → (awaiting_shot | round_end) → … → match_end`, plus `forfeited`, `expired`, `cancelled`.

### A8.4 Live matches
- Nakama real-time match (authoritative match handler), WebSocket connection.
- Heartbeat every 5 s; disconnect after 15 s silence; 30 s reconnect window.
- Opponent sees "Gus is drawing…" while the other player aims (optionally a live preview of their bow angle every 200 ms — [v1.1], remote config).

### A8.5 Async matches
- Stored on the server. Each turn submission triggers a push to the next player.
- Opening the app on your turn: the **replay** of the opponent's shot plays first (skippable), then your aim.
- **Inbox** (screen 20): list of matches in progress, showing opponent, score, whose turn, time left. Max 20 active async matches per player.

### A8.6 Anti-cheat
- Server-side simulation of every counted shot (above).
- **App Attest** (DeviceCheck) assertion attached to every counted request (match turns, Daily Shot, leaderboard). Missing or invalid → the request is processed but **does not count** for leaderboards.
- Rate limits: max 1 counted Daily Shot per account per day; match turn endpoints limited per match.
- Server rejects inputs out of range (angle −100…850 tenths, power 0…1000).
- Flag accounts with statistically impossible accuracy for review.

### A8.7 App Clip [v1.1]
- Invite links open an App Clip (< 15 MB uncompressed limit) that can play **one friend-duel turn** as a guest.
- Uses ephemeral notification permission to tell the friend when the opponent replies.
- Shows the App Store overlay (`SKOverlay`) at the moment the reply arrives: "Install to take your turn."
- Guest identity, match and an invite-only **"Duelist" hat** carry over to the full app via a shared App Group container and the server.

## A9. Accounts and identity

### A9.1 First launch flow
1. App opens → splash → silently attempt **Game Center** authentication (no custom UI if it succeeds; iOS shows its own banner).
2. Create a **device account** on the server (Nakama device auth using a UUID stored in the Keychain). If Game Center succeeded, link its `teamPlayerID` to the account.
3. Show **Pick your name** (`Gamertag.dc.html`) — required once:
   - Gamertag field pre-filled with a generated suggestion (adjective + noun + 2 digits, for example `BraveYew_42`), dice button to reroll.
   - **Country** pre-filled from the iPhone's region (`Locale.current.region`), shown with its flag and "from your iPhone"; "change" opens the Country picker.
   - **Avatar:** the portrait on the left shows a **randomly generated face** (Section A14a) with the gamertag on a banner under it. A small pencil button on the portrait opens the Avatar editor; a dice button rerolls a random face. Editing is optional at this point.
   - Button **LET'S SHOOT** → Home. Disabled until the name is valid and available.
4. First time on Home, a one-line coach mark points at PLAY.

### A9.2 Gamertag rules
- 3–16 characters: letters A–Z / a–z, digits 0–9, underscore. Must start with a letter.
- **Unique**, case-insensitive. Availability checked live (debounced 400 ms) via server RPC.
- Profanity and impersonation filter on the server (word list + reserved names like "admin", "longbow", "gus"). Rejection message is generic: "That name isn't available."
- Shown everywhere with the player's flag.
- Changes: **1 free change**; further changes allowed once every 30 days ([Flag: monetization] can later cost feathers).

### A9.3 Country
- Default: iPhone region. No location permission is ever requested.
- Changeable any time in Settings → Country (`Country.dc.html`): search field, detected country highlighted first, full list of ISO 3166-1 countries with flags and localised names.
- Stored as an ISO 3166-1 alpha-2 code on the server.
- Flags rendered from bundled SVG assets (one per country code), 24 × 16 pt in lists, with a thin ink outline.

### A9.4 Saving progress across devices
- Game Center link gives cross-device continuity automatically when the player uses Game Center.
- Settings → **Save progress** → **Sign in with Apple** (official Apple button) links an Apple ID. Prompt also appears once when the player first reaches the top 10 of their league group ("Save your spot").
- On a new device: Game Center or Sign in with Apple restores the account.

### A9.5 Account deletion (App Store requirement)
- Settings → **Delete account**: confirmation sheet explaining what is deleted, type the gamertag to confirm.
- Server deletes profile, matches and leaderboard entries within 30 days; the gamertag is released after 90 days.

### A9.6 Report and block (App Store requirement for user-generated names)
- Long-press a player's row (leaderboard, match result, inbox) or open their profile → **Report name** / **Block player**.
- Blocked players are never matched with you and their names are hidden from your friends board.
- Reports go to a moderation queue (simple admin view in Nakama console in v1.0).

## A10. Profiles
- Own profile: avatar face (tap → Avatar editor), archer with equipped hat, gamertag, flag, level, league, stats (matches, wins, win rate, headshots, longest hit in metres, best Daily Shot).
- Other players' profiles: same, without editing; buttons Challenge (friend duel), Block, Report.

## A11. Leaderboards and leagues

### A11.1 Structure (`Leaderboard.dc.html`)
- Tabs: **LEAGUE** (default), **FRIENDS**, **GLOBAL**.
- Header: "THIS WEEK", countdown to reset ("resets in 2d 14h").
- Row: rank · avatar (32 pt circle, face wearing the equipped hat) · flag · gamertag · points · movement since yesterday (▲2, ▼1, –).
- Your row is inverted (black fill, paper text) and always visible (pinned at the bottom if scrolled out of view).
- GLOBAL tab has a country filter (All / your country).

### A11.2 Weekly points
| Action | Points (default) |
| --- | --- |
| Online match win | 100 |
| Online match loss (completed, not forfeited) | 20 |
| Round won | 15 |
| Headshot (online) | 10 |
| Daily Shot | score ÷ 10 (0–100) |
- vs AI matches give **no** leaderboard points.
- Only server-validated, App-Attested actions count.
- Same opponent: points from at most 3 matches per day against the same player (anti-farming).

### A11.3 Leagues
- Weekly **groups of 50** players of the same league, assigned at your first counted action of the week.
- Leagues, lowest to highest (named after bow woods): **Birch → Ash → Elm → Hickory → Oak → Yew**.
- End of week (Monday 00:00 UTC): **top 5 promote**, **bottom 5 demote** (none demote from Birch, none promote from Yew). Dashed line under 5th place labelled "top 5 move up" (hand font).
- Weekly rewards (non-monetary): XP bonus by final position; top 3 in Yew get a season-limited hat.
- Inactive players (no counted action that week) are not placed in a group.

### A11.4 Hidden skill rating
- Glicko-2 rating per player for matchmaking (not shown in v1.0). Starts at 1500. Updated after each completed online match.

### A11.5 Weekly reset job
- Server cron at Monday 00:00 UTC: freeze boards, compute promotions/demotions, grant rewards, archive the week, open new groups. Push "Your week is in: you moved up to Oak."

## A12. Progression (no money involved)

### A12.1 XP and levels
| Source | XP |
| --- | --- |
| Match completed (any mode) | 20 |
| Match won | +30 |
| Headshot | 5 |
| Daily Shot played | 15 |
| Weekly league result | 0–100 |
- Level curve: XP to next level = 100 + 40 × (level − 1). No level cap.
- Level-ups unlock arenas and hats (below) and award feathers.

### A12.2 Feathers (soft currency)
- Earned only by playing in v1.0: level-up (50), match win (5), Daily Shot (5), weekly league reward (10–100).
- Spent on hats in the wardrobe.
- Server-side balance; client shows a cached value.
- Daily earning cap from matches: 100 feathers (remote config) to prevent farming.
- [Flag: monetization] Selling feathers for real money is Part B.

### A12.3 Unlock table (v1.0)
| Level | Unlock |
| --- | --- |
| 1 | Hills arena, Visor helmet (default) |
| 3 | Feather cap |
| 5 | Castle arena |
| 7 | Horned helmet |
| 9 | Cooking pot |
| 12 | Windmills arena |
| 15 | Moon arena |
| 20 | Top hat |

## A13. Arenas (`Arenas.dc.html`)
| Arena | Physics | Look | Tag |
| --- | --- | --- | --- |
| **Hills** | Standard: gravity 9.8, wind 0–6 | Rolling hills, halftone sun, clouds, tufts | [v1.0] |
| **Castle** | Archers on two towers (higher, 20–40 m above ground); walls as obstacles | Crenellated towers, flag | [v1.0] |
| **Windmills** | Wind 3–10; turning windmill sails as moving obstacles (deterministic rotation from flight time) | Windmills, wind lines | [v1.0] |
| **Moon** | Gravity 1.6, no wind, very high arcs; longer distances 300–600 m | Inverted look: black sky, paper ground, craters, earth in the sky | [v1.0] |
- Arena select screen: cards with a mini scene and one-word name; locked cards show a lock and the unlock level.
- vs AI and friend duels: the creator picks the arena (or Random). Quick match: random among arenas both players have unlocked. Ranked: Hills and Castle only.

## A14. Cosmetics — hats (`Wardrobe.dc.html`)
- One hat slot in v1.0 ([Later]: bow skin, arrow trail, victory taunt).
- Wardrobe screen: archer on a plinth wearing the selected hat; 3-column grid of hat tiles; selected tile inverted; locked tiles dashed with a lock icon and unlock condition on tap.
- v1.0 hats: Visor helmet, Feather cap, Horned helmet, Cooking pot, Top hat, Crown (league reward), Duelist ([v1.1], App Clip invite).
- Each hat: hand-drawn in 3 line-boil frames; anchor point on the head; small icon version for leaderboard rows; optional hit sound (pot = "clang").
- Hats are visible to opponents in every online match and on leaderboards.
- Purely cosmetic: **no gameplay effect, ever**.

## A14a. Avatars — faces [v1.0]

Every player has a customisable face, built from hand-drawn parts, in the spirit of Notion Faces: black-and-white, bold outlines, a little caricatured, assembled like a paper doll. The face is the player's identity across the whole game — and it is the head of their archer in matches.

### A14a.1 Where the face appears
| Place | Size / view |
| --- | --- |
| Pick your name, Profile, Settings card | Large portrait, front view, 160–240 pt |
| Toss, match result | Portrait, front view, ~140 pt, in a circle |
| Leaderboard rows, inbox, search screen | Small circle, front view, 32 pt |
| Home profile button | 48 pt circle (replaces the generic smiley once customised) |
| **In-game archer head** | **Three-quarter view** facing the opponent, at game scale, with the equipped hat on top |

### A14a.2 Parts (categories, in layer order bottom → top)
| # | Category | v1.0 options (minimum) | Notes |
| --- | --- | --- | --- |
| 1 | Background | 6 | Plain paper, halftone circle, dots, stripes, sunburst, black. Portraits only, not in game. |
| 2 | Head shape | 8 | Round, oval, square, long, pear, heart, wide, small |
| 3 | Skin tone | 5 | Expressed as **halftone density** (paper, light dots, medium dots, dense dots, very dense) — the game stays black and white but supports a range of skin tones |
| 4 | Ears | 4 | Small, big, pointy, none visible |
| 5 | Hair (back layer) | 14 | Long hair parts that sit behind the head |
| 6 | Hair (front) | 24 | Short, buzz, bald, curly, coily, afro, braids, locs, bun, ponytail, bob, fringe, side part, mohawk, wavy, hijab, turban, headscarf, etc. Inclusive of hair textures and head coverings. |
| 7 | Eyebrows | 10 | Thin, thick, angry, worried, unibrow, raised, etc. |
| 8 | Eyes | 14 | Dots, wide, sleepy, winking, smiling arcs, lashes, closed, etc. |
| 9 | Nose | 10 | Button, long, hooked, wide, round, pointed, etc. |
| 10 | Mouth | 14 | Grin, smile, flat, open laugh, gap tooth, tongue out, whistle, etc. |
| 11 | Facial hair | 12 + none | Stubble, moustache styles, goatee, full beard (halftone), Gus's big moustache |
| 12 | Glasses | 8 + none | Round, square, aviators, monocle, eye patch, sunglasses |
| 13 | Extras | 8 + none | Freckles, cheek blush (dots), scar, earrings, nose ring, mole, bandage, face paint stripes |

- Hats (Section A14) layer **on top of everything** and hide the hair-front layer where they overlap (each hat defines which hair styles it masks).
- Bjorn and Gus are built from these same parts and exist as named **presets**.

### A14a.3 Avatar editor (screen 22)
- Landscape layout: **left** — large live preview of the face, and a small preview of the in-game archer wearing it; **right** — category tabs (icons, scrollable row) and a 4-column grid of options for the selected category.
- Selected option is inverted (black tile). Changes apply to the preview instantly.
- **Dice** button: randomise the whole face. Long-press dice on a category tab: randomise only that category.
- **Lock** toggle per category (keeps it when randomising the whole face).
- **Undo / redo** (up to 20 steps).
- **Presets** row: Bjorn, Gus, plus 6 more starter faces.
- **Done** saves to the server; **Cancel** discards changes (confirm if there are changes).
- Skin tone shown as 5 round swatches of increasing dot density, not colours.
- Every option has an accessibility label ("Hair: curly", "Glasses: round").

### A14a.4 Data model
The avatar is stored as a small config, never as an image:
```json
{ "v": 1, "bg": 2, "head": 1, "skin": 3, "ears": 0, "hairBack": null, "hairFront": 7,
  "brows": 4, "eyes": 2, "nose": 5, "mouth": 1, "facialHair": 6, "glasses": null, "extras": [3] }
```
- Option ids are stable integers per category; never reuse an id. Adding options later only appends.
- `v` = schema version for future migrations.
- Stored in `profiles.avatar` on the server; sent with every player summary (leaderboard rows, match data), so opponents render your face locally from bundled parts.

### A14a.5 Rendering
- Each option is a vector asset (PDF or SVG in the asset catalogue) in **two views**: `front` and `threeQuarter`. Each view comes in the 3 line-boil frames.
- Parts share anchor points per head shape (eye line, nose point, mouth line, chin, hairline, ear points) so any combination lines up. Head shape assets define the anchors; other parts are positioned relative to them.
- Skin tone is applied by the halftone shader (density parameter) to the head and ears fill, not by separate assets.
- Composite in SwiftUI for menus and as layered `SKSpriteNode`s for the in-game head. Cache rendered portraits by `hash(avatar config + hat + size)`.
- In game, the head reacts with expressions (Section A4): expression overrides replace eyes and mouth temporarily (hit: spiral eyes + open mouth; relieved: sweat drops; victorious: big grin), regardless of the chosen eyes and mouth.

### A14a.6 Rules
- Free text or free drawing is **not** allowed in the avatar — only parts — so no moderation is needed.
- New players get a random face on account creation (random within all free parts).
- Some parts unlock by level or league as extra rewards (for example "laurel" extra for reaching Yew league); locked options show a lock and the condition.
- Changing the face is always free and unlimited.
- [Flag: monetization] premium face parts are Part B (B3.6).

### A14a.7 Server and analytics
- RPC `setAvatar(config)` — validates every id exists and is unlocked for the player; rejects otherwise.
- Analytics: `avatar_editor_opened`, `avatar_saved` (categories changed, randomised yes/no, preset used).

## A15. Audio
| Sound | When |
| --- | --- |
| Bowstring creak (pitch rises with power) | While drawing |
| Twang | Release |
| Whoosh (doppler, follows camera) | Flight |
| Thunk (wood/dirt variants) | Ground or obstacle hit |
| Thwack + voice grunt | Body/leg hit |
| Clang/bonk variants | Headshot (plus hat-specific variant) |
| Crowd-less "ooh" whistle | Near miss |
| Spin and click | Toss |
| Short jingles | Round won, match won, level up, promotion |
| UI clicks | Buttons, toggles |
- Music: one calm, minimal loop for menus; off during aiming. Separate volume toggles for Sound and Music.
- All audio respects the silent switch for music; sound effects follow the user's Sound setting.

## A16. Haptics
- Light tick every 5 % of draw power; medium impact on release; heavy impact on taking a hit; success pattern on headshot; selection feedback on toggles and tabs.
- Settings → Haptics on/off.

## A17. Notifications
| Notification | Trigger | Tag |
| --- | --- | --- |
| "Gus shot at you. Your turn." | Async turn | [v1.0] |
| "4 hours left to take your shot against Gus." | Async turn at 20 h | [v1.0] |
| "Gus accepted your duel." | Friend joined via code/link | [v1.0] |
| "Today's Daily Shot is ready." | Once a day at the player's chosen local time (default 18:00), only if not yet played | [v1.0] |
| "Your week is in: you moved up to Oak." | Weekly reset | [v1.0] |
- Ask for notification permission **after the first async match is created** or the first Daily Shot is played — never on first launch.
- Each type can be switched off in Settings → Notifications.

## A18. Settings (`Settings.dc.html`)
Left: profile card (archer, flag, gamertag, level, league). Right, in order:
1. Gamertag ›
2. Country › (flag + name)
3. Sound (switch)
4. Music (switch)
5. Haptics (switch)
6. Notifications › (per-type switches, Daily Shot reminder time)
7. Aim guide (switch; on by default, off disables the short dotted guide) [v1.1]
8. Save progress — Sign in with Apple button (or "Signed in with Apple" when linked)
9. Restore purchases — **[Flag: monetization] hidden in v1.0**
10. Privacy policy, Terms ›
11. Support / send feedback ›
12. Delete account (quiet text button at the bottom)
- Footer: app version and build.

## A19. Accessibility
- Dynamic Type for menu text up to XXL (in-game HUD stays fixed but uses large sizes).
- VoiceOver labels for every button, toggle and flag ("Canada"); leaderboard rows read as "4th, Bjorn_NL, Canada, 1,984 points, up 2".
- Reduce Motion: no screen shake, no line boil, shorter camera moves, no parallax.
- Colour is never the only carrier of meaning (the game is monochrome).
- Left-handed friendly: drag anywhere on the screen.
- [v1.1] Assisted aim option (longer aim guide) for players with motor difficulties; matches with assisted aim don't count for leaderboards.

## A20. Localisation
- v1.0 languages: English, French (Canada). All strings in String Catalogs from day one.
- Country names via `Locale.localizedString(forRegionCode:)`.
- Numbers and dates formatted with the user's locale.

## A21. Analytics events
Every event includes: `accountId` (pseudonymous), `appVersion`, `sessionId`, `timestamp`.
| Event | Properties |
| --- | --- |
| `app_open` | `isFirstLaunch` |
| `gamertag_created` | `wasSuggested`, `countryChanged` |
| `match_start` | `mode` (ai/friend_live/friend_async/quick/ranked), `difficulty`, `arena` |
| `shot_taken` | `mode`, `round`, `turn`, `angleTenths`, `powerPermille`, `result`, `damage`, `distanceToTarget` |
| `brace_attempt` | `outcome` (perfect/good/miss) |
| `match_end` | `mode`, `outcome`, `rounds`, `durationS`, `forfeit` |
| `daily_shot_played` | `score`, `rank` |
| `invite_sent` / `invite_opened` / `invite_joined` | `channel` |
| `leaderboard_viewed` | `tab` |
| `league_result` | `league`, `position`, `promoted`, `demoted` |
| `hat_equipped` / `hat_unlocked` | `hatId`, `source` |
| `level_up` | `level` |
| `notification_opened` | `type` |
| `settings_changed` | `key`, `value` |
| `sim_mismatch` | `matchId`, `turn` (client vs server result differed) |
Key metrics to dashboard: D1/D7/D30 retention, matches per DAU, invites per player, invite conversion, Daily Shot participation, async match completion rate.

## A22. Backend (Nakama)

### A22.1 Data
| Collection | Key fields |
| --- | --- |
| `profiles` | accountId, gamertag, gamertagLower (unique index), country, avatar (config, A14a.4), unlockedAvatarParts[], level, xp, feathers, equippedHat, unlockedHats[], unlockedArenas[], rating (Glicko-2 r/RD/σ), stats{}, blocked[], createdAt |
| `matches` | matchId, code, mode, pace, arena, players[], seed, rounds[], currentTurn, state, deadlines, createdAt |
| `shots` | matchId, round, turn, shooter, inputs, result, serverTime |
| `daily_shots` | date, accountId, inputs, score, attested |
| `league_groups` | weekId, league, groupId, members[], points per member |
| `reports` | reporter, reported, reason, createdAt, status |
| `config` | remote config and feature flags (A23) |

### A22.2 RPCs
`checkGamertag`, `setGamertag`, `setCountry`, `setAvatar`, `getProfile`, `equipHat`, `unlockHat`, `createFriendMatch`, `joinMatchByCode`, `listMyMatches`, `submitShot`, `forfeitMatch`, `requestQuickMatch`, `cancelQuickMatch`, `getDailyShot`, `submitDailyShot`, `getLeaderboard(tab, country?)`, `getConfig`, `reportPlayer`, `blockPlayer`, `deleteAccount`, `linkGameCenter`, `linkApple`.

### A22.3 Jobs
- Weekly league reset (Monday 00:00 UTC).
- Async match expiry check (every 15 min).
- Daily Shot rollover (00:00 UTC).
- Daily Shot reminder pushes (hourly, per time zone).

### A22.4 Environments
- `dev`, `staging`, `production`. The app chooses by build configuration. TestFlight builds use staging.

## A23. Feature flags and remote config
Fetched at launch (cached; bundled defaults if offline). Flags are booleans unless noted.

| Key | Default v1.0 | Purpose |
| --- | --- | --- |
| `dailyShotEnabled` | true | Daily Shot mode |
| `quickMatchEnabled` | true | Random matchmaking |
| `asyncMatchesEnabled` | true | 1 shot / day pace |
| `leaguesEnabled` | true | Weekly leagues |
| `braceEnabled` | true | Brace mechanic |
| `aimGuidePercent` (number) | 15 | Visible part of the aim guide |
| `roundsToWin` (number) | 3 | Match length |
| `physics.*` (numbers) | see A6.3 | Gravity, speeds, drag, wind ranges |
| `damage.*` (numbers) | 50/25/15 | Hit damage |
| `points.*` (numbers) | see A11.2 | League points |
| `xp.*`, `feathers.*` (numbers) | see A12 | Progression |
| `lineBoilEnabled` | true | Animated line boil |
| `rankedEnabled` | false | [v1.1] |
| `appClipInvitesEnabled` | false | [v1.1] |
| `liveAimPreviewEnabled` | false | [v1.1] |
| `allowAsymmetricMaps` | false | [v1.1] |
| `monetization.*` | **all false** | PART B |
| `minimumAppVersion` (string) | "1.0.0" | Force-update screen for older clients |

## A24. Privacy and App Store compliance
- Privacy nutrition label: account identifiers, gameplay data, crash data; no tracking in v1.0.
- No App Tracking Transparency prompt in v1.0 (no ads). [Flag: monetization] Part B may add it.
- Account deletion in app (A9.5); report and block (A9.6).
- Sign in with Apple only alongside Game Center — no Google/Facebook login.
- Age rating: 9+ (cartoon/fantasy violence: arrows, no blood). Hits are comedic (spiral eyes, bonk sounds); no blood or gore anywhere.
- Privacy policy and terms URLs in Settings and App Store Connect.

## A25. Release plan and acceptance criteria

### Milestone 1 — Core (offline)
- Aim, physics, camera, hits, near miss, rounds, match, toss, results vs AI (3 difficulties), Hills arena.
- **Done when:** golden-vector tests pass; a full match vs AI plays start to finish at 60 fps on iPhone 12; no crash in 100 automated AI-vs-AI matches.

### Milestone 2 — Identity and online
- Device + Game Center account, gamertag, country, settings; friend duels live + async; quick match; push notifications; server-authoritative shots.
- **Done when:** two devices complete live and async matches with identical results; the server rejects tampered inputs; account deletion works end to end.

### Milestone 3 — Retention
- Daily Shot, weekly leagues and leaderboard, XP, feathers, hats, all four arenas, brace, audio, haptics, analytics.
- **Done when:** a weekly reset runs correctly on staging with 500 simulated players; all analytics events arrive.

### Milestone 4 — Soft launch (Canada)
- App Store release in Canada only. Watch retention gates:

| | D1 | D7 | D30 |
| --- | --- | --- | --- |
| Rethink | < 35 % | < 12 % | < 5 % |
| Iterate | 35–45 % | 12–20 % | 5–10 % |
| Scale globally | ≥ 45 % | ≥ 20 % | ≥ 10 % |

### Milestone 5 — v1.1
- Ranked, App Clip invites, practice range, Gus the Legend, live aim preview, monetization switched on (Part B) if soft-launch data supports it.

## A26. Open decisions
1. Final game name (affects bundle display name, wordmark, App Store listing).
2. Character roster beyond Bjorn and Gus.
3. Whether flags show at full colour or slightly faded (design check on device).
4. Music: commission or licence.

---

# PART B — MONETIZATION (OFF IN v1.0)

## B1. Principle
- Monetization is **completely disabled** in the first release. No store screen, no ads SDK initialised, no purchase code executed, no tracking prompt.
- It must be possible to switch it on **later without restructuring the app** — ideally without an app update for anything already built and approved.

## B2. How the switch works

### B2.1 Master and sub-flags (remote config)
| Key | v1.0 | Controls |
| --- | --- | --- |
| `monetization.enabled` | false | **Master switch.** If false, every other monetization flag is treated as false. |
| `monetization.shopEnabled` | false | Shop screen and its home-screen entry |
| `monetization.iapEnabled` | false | StoreKit purchases (cosmetics, feather packs, supporter pack) |
| `monetization.seasonPassEnabled` | false | Season pass track and purchase |
| `monetization.rewardedAdsEnabled` | false | Opt-in rewarded ads |
| `monetization.premiumAccentEnabled` | false | Red accent rendering on premium cosmetics |
| `monetization.paidNameChangeEnabled` | false | Gamertag changes cost feathers |
| `monetization.streakProtectionEnabled` | false | Rewarded ad to protect a Daily Shot streak |
| `monetization.prices.*` | — | Feather prices of items, product id mapping |

Also a **compile-time** flag `MONETIZATION_COMPILED` (Swift active compilation condition). v1.0 can ship with it **off**, so the ads SDK and StoreKit code are not even linked. The first monetized release turns it on and ships the code dormant (remote flags still false), then remote config switches features on gradually.

### B2.2 Code structure
```swift
protocol MonetizationService {
    var isEnabled: Bool { get }                       // master flag
    func isEnabled(_ feature: MonetizationFeature) -> Bool
    func products(for placement: StorePlacement) async -> [StoreProduct]
    func purchase(_ productId: String) async throws -> PurchaseResult
    func restorePurchases() async throws
    func canShowRewardedAd(for placement: AdPlacement) -> Bool
    func showRewardedAd(for placement: AdPlacement) async -> AdResult
}

enum MonetizationFeature { case shop, iap, seasonPass, rewardedAds, premiumAccent, paidNameChange, streakProtection }
```
- `NoOpMonetizationService` (v1.0): `isEnabled == false`, every feature disabled, `products` returns `[]`, `canShowRewardedAd` returns false.
- `LiveMonetizationService` (later): StoreKit 2 + the chosen ads SDK, reading the flags.
- The dependency container picks the implementation from `MONETIZATION_COMPILED` and `monetization.enabled`.

### B2.3 UI slots
- Every place where monetization will appear is a **slot view** in the UI that asks the service whether to render. When disabled, the slot renders **nothing** and takes **no space**:
  - `ShopEntrySlot` (home screen corner)
  - `RewardedAdSlot(placement:)` (match result, Daily Shot result, streak)
  - `PremiumBadgeSlot` (wardrobe tiles)
  - `SeasonTrackSlot` (home and results)
  - `RestorePurchasesSlot` (settings)
- Build these slots in v1.0 as empty views, so turning monetization on is configuration, not layout work.

### B2.4 Server side
- Purchases are verified on the server (App Store Server API / signed transactions) before granting items.
- Entitlements stored in `profiles.entitlements[]` (supporter, seasonPass(seasonId), items).
- Server also reads `monetization.*` flags so a disabled feature can never grant anything.

## B3. Monetization features (designed, disabled)

### B3.1 Rewarded ads (opt-in only)
| Placement | Reward |
| --- | --- |
| Casual match result | Double feathers from that match |
| Daily Shot result | One extra **practice** attempt with the replay camera (never a counted attempt) |
| Daily Shot streak | Protect a broken streak once per week |
| Wardrobe | Try a locked hat for 3 matches [Later] |
- Never shown in ranked, never during a match, never forced (no interstitials).
- Frequency cap: 6 rewarded ads per day per player (remote config).
- Requires ATT prompt only if the ads SDK uses tracking; prefer non-tracking mode first.

### B3.2 In-app purchases (StoreKit 2)
| Product | Type | Contents |
| --- | --- | --- |
| Starter pack | Non-consumable, one-time | 3 hats + 500 feathers |
| Supporter pack | Non-consumable | No ads ever, exclusive hat, 10 % season pass discount |
| Feather packs (S/M/L) | Consumable | Feathers |
| Premium hats | Paid in feathers | Items with the red premium accent |
- Prices set in App Store Connect; display order and featured items from remote config.

### B3.3 Season pass
- 6-week seasons. Track of ~30 tiers filled by XP from matches and Daily Shots.
- Free track: feathers, some hats. Paid track: premium hats, arrow trails, victory taunts, a new AI challenge.
- Never contains anything that affects gameplay or ranked.

### B3.4 Premium accent colour
- When `monetization.premiumAccentEnabled` is true, premium cosmetics render a single red element (`premiumAccent`). The rest of the game stays black and white.

### B3.5 Paid extras
- Gamertag change beyond the free one costs feathers.
- [Later] Apple Arcade as an alternative business model (no IAP, no ads) — if chosen, `MONETIZATION_COMPILED` stays off permanently.

### B3.6 Premium face parts
- Extra avatar parts (hair styles, glasses, extras, backgrounds) bought with feathers or in packs, some with the red premium accent (for example a red bandana).
- Free parts always cover every category fully, so nobody has to pay to look like themselves.

## B4. Hard rules (apply forever)
1. **Ranked and leaderboards are never affected by money or ads.** No boosts, consumables or purchases change rating, points or match outcomes.
2. Cosmetics never change hitboxes, visibility or physics.
3. No forced ads. No loot boxes or random paid rewards.
4. Every purchase can be restored (Settings → Restore purchases).
5. Turning `monetization.enabled` off at any time must leave the game fully playable, with purchased items still owned.

## B5. Acceptance criteria for the switch
- With all flags false (v1.0): no store UI visible anywhere, no network calls to ad or store services, no ATT prompt, app passes review as a free game with no purchases.
- Flipping `monetization.enabled` and one sub-flag on staging shows exactly that feature and nothing else, without an app restart beyond the next config fetch.
- Flipping it off again hides the feature on next launch; owned items remain.