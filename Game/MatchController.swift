import LongbowCore
import os
import SpriteKit
import SwiftUI

/// Turn-by-turn trace for online duels (kept by the system log).
private let duelLog = Logger(subsystem: "com.tejusrevi.longbow", category: "duel")

/// vs the computer (A7.1), two people passing one phone, or a friend duel
/// over the internet (A7.2).
enum MatchMode: Equatable {
    case vsAI(AIDifficulty)
    case passAndPlay
    case online(OnlineMatch)

    var difficulty: AIDifficulty? {
        if case let .vsAI(d) = self { return d }
        return nil
    }

    var isOnline: Bool {
        if case .online = self { return true }
        return false
    }

    var analyticsName: String {
        switch self {
        case .vsAI: return "ai"
        case .passAndPlay: return "pass_and_play"
        case .online: return "friend_live"
        }
    }
}

/// A running friend duel: the connection plus what the server said at the start.
struct OnlineMatch: Equatable {
    let duel: FriendDuel
    let start: DuelStart

    static func == (a: OnlineMatch, b: OnlineMatch) -> Bool { a.duel === b.duel }
}

/// Result of a finished match, for the result screen (spec A6.9).
struct MatchSummary: Identifiable, Equatable {
    let id = UUID()
    let mode: MatchMode
    let names: [String]
    let winner: Int
    let score: [Int]
    /// Arrows the winner landed on the loser (drawn on the loser's portrait).
    let arrowsLanded: Int
    let headshots: Int
    let xpBefore: Int
    let rewards: MatchRewards?
    let forfeited: Bool
    /// Which side this device played (0 = left).
    var me: Int = 0
    var avatars: [Avatar] = [.bjorn, .gus]
    var hats: [Hat] = [.none, .none]
    /// Set when the opponent left an online match early.
    var opponentLeft = false
    /// Health each archer finished on (the winner's is the headline).
    var health: [Int] = [0, 0]

    var won: Bool { winner == me }
}

/// Runs a match: owns the Core `MatchEngine` (and the AI for vs-AI play) and
/// drives `MatchScene`. Player 0 is on the left; player 1 is the AI or, in pass
/// and play, the second person.
@MainActor
final class MatchController: ObservableObject {
    enum Phase: Equatable {
        case intro, aiming, aiThinking, flying, presenting, between, over
    }

    struct Banner: Equatable {
        let title: String
        let subtitle: String?
    }

    /// Everything the flight mini-map draws, in world metres (y up), so it can
    /// be drawn at one true scale: same arc, same angles as the real flight.
    struct Minimap: Equatable {
        /// The whole flight path, thinned.
        let path: [CGPoint]
        /// The arrow right now, and its direction of travel (radians).
        let arrow: CGPoint
        let heading: CGFloat
        /// How much of `path` has been flown.
        let flown: Int
        let ground: [CGPoint]
        /// Feet of archer 0 and 1, and how tall they stand.
        let archers: [CGPoint]
        let archerHeight: CGFloat
        let shooter: Int
        /// World x the strip covers: both archers plus 20% of the gap past
        /// each, the same whoever shoots. Anything beyond is clipped off.
        let span: ClosedRange<CGFloat>
    }

    @Published private(set) var phase: Phase = .intro
    @Published private(set) var health: [Int]
    @Published private(set) var roundsWon = [0, 0]
    @Published private(set) var round = 1
    /// Wind for the current shooter in world terms (positive blows right).
    @Published private(set) var windWorld: Double = 0
    @Published private(set) var timeLeft: Double?
    @Published private(set) var banner: Banner?
    @Published private(set) var minimap: Minimap?
    @Published private(set) var flightDistance: Int?
    /// Short hand-written prompt under the wind ("player 2, you're up.").
    @Published private(set) var turnNote: String?
    @Published var paused = false {
        didSet {
            scene.isGamePaused = paused
            // Also freezes running actions (the AI's draw, impact holds).
            scene.isPaused = paused
        }
    }

    @Published var slowMotion = false {
        didSet { scene.playbackRate = slowMotion ? 0.3 : 1 }
    }

    let names: [String]
    /// Online players' two-letter countries, shown beside their names ("" offline).
    let countries: [String]
    let mode: MatchMode
    let difficulty: AIDifficulty
    /// Players controlled by touch.
    let humans: Set<Int>
    /// The side this device plays (0 = left; pass and play counts as 0).
    let me: Int
    let avatars: [Avatar]
    let hats: [Hat]
    private var online: OnlineMatch? { if case let .online(o) = mode { return o }; return nil }
    /// Official results from the server, by turn.
    private var serverResults: [Int: DuelResult] = [:]
    /// What this device computed for each turn, to check against the server.
    private var localReports: [Int: TurnReport] = [:]
    private var opponentLeft = false
    /// This device and the server disagree: rebuild from the server's history.
    private var needsResync = false
    let services: Services
    let scene: MatchScene
    var onFinish: ((MatchSummary) -> Void)?

    private(set) var engine: MatchEngine
    private var ai: AIPlayer
    /// DEBUG `-autoplay` launch argument: the AI also plays the human side, for
    /// soak-testing whole matches in the real app.
    private var autoplayAI: AIPlayer?
    private var lastShot: [ShotOutcome?] = [nil, nil]
    private let startedAt = Date()
    private var aiTask: Task<Void, Never>?
    /// The AI starts thinking as soon as it knows it's next (during the camera
    /// pan), so there's no dead air once its turn begins.
    private var aiPlan: Task<(ShotInput, AIPlayer), Never>?
    private(set) var isAIDrawing = false
    private var finished = false

    // Stats for the human (player 0) and shot medals.
    private var stats: MatchStats
    private var hitStreak = [0, 0]
    private var damageTakenThisRound = [0, 0]

    var config: AppConfig { services.config }

    init(mode: MatchMode, seed: UInt64, services: Services, sceneSize: CGSize) {
        self.mode = mode
        let difficulty = mode.difficulty ?? .medium
        self.difficulty = difficulty
        var names = mode == .passAndPlay ? ["PLAYER 1", "PLAYER 2"] : ["YOU", "GUS"]
        var countries = ["", ""]
        var avatars: [Avatar] = [services.progress.avatar, .gus]
        var hats: [Hat] = [services.progress.equippedHat, mode == .passAndPlay ? .featherCap : .none]
        if case let .online(o) = mode {
            humans = [o.start.seat]
            me = o.start.seat
            names = o.start.players.map(\.name)
            names[o.start.seat] = "YOU"
            countries = o.start.players.map(\.country)
            avatars = o.start.players.map(\.avatar)
            hats = o.start.players.map(\.hat)
        } else {
            humans = mode == .passAndPlay ? [0, 1] : [0]
            me = 0
        }
        self.avatars = avatars
        self.hats = hats
        #if DEBUG
        // `-playerName BraveYew_42` tests long gamertags in the HUD.
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-playerName"),
           i + 1 < ProcessInfo.processInfo.arguments.count {
            names[0] = ProcessInfo.processInfo.arguments[i + 1]
        }
        #endif
        self.names = names
        self.countries = countries
        stats = MatchStats(won: false, difficulty: difficulty)
        self.services = services
        let config = services.config
        var game = config.game
        // Every difficulty is first to the same number of rounds; what changes is
        // how hard each hit is (wind, knockback, aim guide) and the AI's skill.
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-oneHitKills") {
            game.damage.head = 100; game.damage.body = 100; game.damage.legs = 100
        }
        #endif
        var setup = MatchSetup(seed: seed, arena: .hills, roundsToWin: game.rules.roundsToWin,
                               firstShooter: MatchSetup.tossWinner(seed: seed),
                               challenge: HitChallenge(rawValue: difficulty.rawValue) ?? .medium)
        if case let .online(o) = mode {
            // Exactly what the server set up, so both sides play the same match.
            setup = MatchSetup(seed: o.start.seed, arena: .hills, roundsToWin: o.start.roundsToWin,
                               firstShooter: o.start.firstShooter, challenge: o.start.challenge)
        }
        engine = MatchEngine(setup: setup, config: game)
        ai = AIPlayer(difficulty: difficulty, seed: seed &+ 0xA1)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-autoplay") {
            autoplayAI = AIPlayer(difficulty: .hard, seed: seed &+ 0xB2)
        }
        #endif
        health = engine.state.health
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        scene = MatchScene(size: sceneSize, appConfig: config, reduceMotion: reduceMotion, hats: hats, avatars: avatars)
        scene.controller = self
    }

    var roundsToWin: Int { engine.state.setup.roundsToWin }
    var firstShooter: Int { engine.state.setup.firstShooter }
    var distance: Double { engine.state.conditions.distance }

    func start() {
        services.analytics.log("match_start", ["mode": mode.analyticsName,
                                               "difficulty": difficulty.rawValue, "arena": "hills"])
        if let online {
            online.duel.attach { [weak self] r in self?.serverResult(r) }
            online.duel.onEnd = { [weak self] winner, reason in self?.serverEnded(winner: winner, reason: reason) }
            online.duel.onPresence = { [weak self] seat, away in self?.opponentPresence(seat: seat, away: away) }
        }
        services.audio.playMusic(.duel)
        beginRound()
    }

    private func beginRound() {
        lastShot = [nil, nil]
        damageTakenThisRound = [0, 0]
        health = engine.state.health
        round = engine.state.round
        scene.loadRound(engine.state.conditions)
        updateWind()
        planAIShotIfNeeded()
        phase = .intro
        scene.openingPan(to: engine.state.currentShooter) { [weak self] in
            self?.beginTurn()
        }
    }

    private func updateWind() {
        windWorld = engine.state.conditions.windRelative * RoundConditions.facing(engine.state.currentShooter)
    }

    private func beginTurn() {
        guard !finished else { return }
        if needsResync { return resyncFromServer() }
        updateWind()
        let shooter = engine.state.currentShooter
        if online != nil {
            duelLog.notice("beginTurn turn=\(self.engine.state.turn) shooter=\(shooter) me=\(self.me) round=\(self.engine.state.round) first=\(self.engine.state.roundFirstShooter) phase=\(String(describing: self.engine.state.phase), privacy: .public)")
        }
        // Our turn has really started: the server starts our shot clock now.
        if let online, shooter == me { online.duel.sendReady(turn: engine.state.turn) }
        if humans.contains(shooter) && !(shooter == me && autoplayAI != nil) {
            phase = .aiming
            timeLeft = config.game.rules.shotTimeLimitSeconds
            exactTimeLeft = nil
            scene.beginHumanAim(shooter: shooter, lastBreath: engine.state.lastBreath, ghostShot: lastShot[shooter])
            // The server already played this turn for us (the clock ran out while we were away).
            if online != nil, let r = serverResults[engine.state.turn], r.shooter == me { applyServerShot(r) }
            // A protest is under way nearby: a flutter of wings, once a round.
            if mode == .passAndPlay {
                withAnimation { turnNote = "\(names[shooter].lowercased()), you're up." }
                scene.run(.wait(forDuration: 2.2)) { [weak self] in withAnimation { self?.turnNote = nil } }
            }
        } else if online != nil && shooter != me {
            phase = .aiThinking
            scene.setLastBreath(engine.state.lastBreath ? shooter : nil)
            if let r = serverResults[engine.state.turn] { playRemote(r) } else if !opponentLeft {
                withAnimation { turnNote = "\(names[shooter].lowercased()) is aiming..." }
            }
        } else {
            phase = .aiThinking
            scene.setLastBreath(engine.state.lastBreath ? shooter : nil)
            runAITurn(shooter: shooter)
        }
    }

    var currentShooter: Int { engine.state.currentShooter }

    /// Starts the AI's search for the upcoming shot in the background.
    private func planAIShotIfNeeded() {
        let shooter = engine.state.currentShooter
        let autoplaysMe = shooter == me && autoplayAI != nil
        guard engine.state.phase == .awaitingShot, autoplaysMe || (online == nil && !humans.contains(shooter)) else { return }
        let engineCopy = engine
        var aiCopy = autoplaysMe ? autoplayAI! : ai
        aiPlan = Task.detached(priority: .userInitiated) {
            let shot = aiCopy.chooseShot(engine: engineCopy)
            return (shot, aiCopy)
        }
    }

    private func runAITurn(shooter: Int) {
        if aiPlan == nil { planAIShotIfNeeded() }
        let plan = aiPlan
        aiPlan = nil
        let autoplaysMe = shooter == me && autoplayAI != nil
        var thinker = autoplaysMe ? autoplayAI! : ai
        let think = thinker.thinkTime()
        aiTask = Task { [weak self] in
            let started = Date()
            guard let input = await plan?.value else { return }
            guard let self, !Task.isCancelled else { return }
            if autoplaysMe { self.autoplayAI = input.1 } else { self.ai = input.1 }
            let remaining = max(0.9, think + 0.9 - Date().timeIntervalSince(started))
            self.isAIDrawing = true
            self.scene.animateAIDraw(input.0, shooter: shooter, duration: remaining) { [weak self] in
                guard let self else { return }
                self.isAIDrawing = false
                // DEBUG autoplay online: the stand-in AI's shot goes to the server like a person's.
                self.submit(autoplaysMe ? self.sendOwnShot(input.0) : input.0)
            }
        }
    }

    /// Called by the scene when the player lets go.
    func humanReleased(_ input: ShotInput) {
        timeLeft = nil
        exactTimeLeft = nil
        submit(sendOwnShot(input))
    }

    /// Sends our shot to the server — unless the server already fired this
    /// turn for us, in which case its shot is the one that counts.
    private func sendOwnShot(_ input: ShotInput) -> ShotInput {
        guard let online else { return input }
        if let r = serverResults[engine.state.turn], r.shooter == me { return r.input }
        online.duel.sendShot(turn: engine.state.turn, input: input.clamped(config.game.aim))
        return input
    }

    // MARK: Online

    /// The server's official result for a turn.
    private func serverResult(_ r: DuelResult) {
        duelLog.notice("serverResult turn=\(r.turn) shooter=\(r.shooter) a=\(r.input.angleTenths) p=\(r.input.powerPermille) timedOut=\(r.timedOut) local=\(self.localReports[r.turn] != nil) engineTurn=\(self.engine.state.turn) phase=\(String(describing: self.phase), privacy: .public)")
        serverResults[r.turn] = r
        if let mine = localReports[r.turn] {
            // Already played here: check the server agrees.
            if mine.health != r.health || mine.input != r.input {
                services.analytics.log("sim_mismatch", ["turn": r.turn, "local": "\(mine.health)", "server": "\(r.health)"])
                needsResync = true
                // Idle and waiting? Catch up right away; otherwise at the next turn.
                if phase == .aiThinking && !isAIDrawing { resyncFromServer() }
            }
            return
        }
        guard r.turn == engine.state.turn, engine.state.phase == .awaitingShot else { return }
        if r.shooter == me, phase == .aiming {
            applyServerShot(r)
        } else if r.shooter != me, phase == .aiThinking {
            playRemote(r)
        }
    }

    /// Rebuilds the match from the server's official results and carries on
    /// from there. Only happens if this device fell out of step.
    private func resyncFromServer() {
        duelLog.notice("resync from server, \(self.serverResults.count) results")
        needsResync = false
        aiTask?.cancel()
        isAIDrawing = false
        var e = MatchEngine(setup: engine.state.setup, config: engine.config)
        for t in serverResults.keys.sorted() {
            if case .roundOver = e.state.phase { e.startNextRound() }
            guard e.state.phase == .awaitingShot, t == e.state.turn, let r = serverResults[t] else { break }
            let report = e.submit(r.input)
            localReports[t] = report
        }
        if case .roundOver = e.state.phase { e.startNextRound() }
        engine = e
        health = engine.state.health
        roundsWon = engine.state.roundsWon
        round = engine.state.round
        services.analytics.log("duel_resync", ["turn": engine.state.turn])
        if engine.state.isOver {
            finish(forfeited: false)
            return
        }
        scene.loadRound(engine.state.conditions)
        updateWind()
        phase = .presenting
        scene.panTo(shooter: engine.state.currentShooter) { [weak self] in self?.beginTurn() }
    }

    /// The server fired our shot for us (our clock ran out).
    private func applyServerShot(_ r: DuelResult) {
        guard phase == .aiming else { return }
        scene.endHumanAim()
        timeLeft = nil
        exactTimeLeft = nil
        submit(r.input)
    }

    /// The opponent's shot: draw the bow, then let it fly.
    private func playRemote(_ r: DuelResult) {
        withAnimation { turnNote = nil }
        isAIDrawing = true
        scene.animateAIDraw(r.input, shooter: r.shooter, duration: 1.1) { [weak self] in
            self?.isAIDrawing = false
            self?.submit(r.input)
        }
    }

    private func serverEnded(winner: Int, reason: String) {
        guard !finished else { return }
        switch reason {
        case "won":
            break // the last result plays out here and ends the match on its own
        case "forfeit" where winner == me, "left" where winner == me:
            // The other archer walked off. Their loss.
            opponentLeft = true
            engine.forfeit(by: 1 - me)
            aiTask?.cancel()
            withAnimation { turnNote = nil }
            showBanner(Banner(title: "YOU WIN", subtitle: "\(names[1 - me].lowercased()) left the duel")) { [weak self] in
                self?.finish(forfeited: false)
            }
        default:
            // We were dropped (or forfeited from elsewhere).
            showBanner(Banner(title: "DISCONNECTED", subtitle: "the duel ended")) { [weak self] in
                guard let self else { return }
                self.engine.forfeit(by: self.me)
                self.finish(forfeited: true)
            }
        }
    }

    private func opponentPresence(seat: Int, away: Bool) {
        guard seat != me, !finished else { return }
        withAnimation { turnNote = away ? "\(names[seat].lowercased()) lost connection..." : nil }
        if !away, phase == .aiThinking, serverResults[engine.state.turn] == nil {
            withAnimation { turnNote = "\(names[seat].lowercased()) is aiming..." }
        }
    }

    func preview(_ input: ShotInput) -> ShotOutcome {
        engine.preview(input)
    }

    /// How much of the trajectory the aim guide shows this match.
    var aimGuidePercent: Double { engine.state.setup.challenge.aimGuidePercent }

    /// The field as it was when the arrow left the bow (archers may be
    /// knocked back once it lands).
    private var flightConditions: RoundConditions?

    private func submit(_ input: ShotInput) {
        guard !finished, engine.state.phase == .awaitingShot else { return }
        let shooter = engine.state.currentShooter
        flightConditions = engine.state.conditions
        // Brace arrives in Milestone 3; until then every hit lands in full.
        let report = engine.submit(input, braceMultiplier: 1)
        localReports[report.turn] = report
        if online != nil {
            duelLog.notice("submit turn=\(report.turn) shooter=\(report.shooter) a=\(report.input.angleTenths) p=\(report.input.powerPermille) events=\(report.events.map { String(describing: $0) }.joined(separator: ","), privacy: .public)")
        }
        if let server = serverResults[report.turn], server.health != report.health {
            services.analytics.log("sim_mismatch", ["turn": report.turn, "local": "\(report.health)", "server": "\(server.health)"])
        }
        if online == nil { if shooter == 1 { ai.observe(report) } else { autoplayAI?.observe(report) } }
        lastShot[shooter] = report.outcome
        let medals = track(report)
        services.analytics.log("shot_taken", [
            "mode": mode.analyticsName, "round": report.round, "turn": report.turn,
            "angleTenths": report.input.angleTenths, "powerPermille": report.input.powerPermille,
            "result": report.outcome.hitPart?.rawValue ?? "miss", "damage": report.damage,
            "distanceToTarget": report.missDistance ?? 0,
        ])
        phase = .flying
        scene.playShot(report, medals: medals) { [weak self] in
            self?.afterShot(report)
        }
    }

    /// Updates match stats and returns the medals this shot earned (shown by the
    /// scene at impact). Medals are for people, not for the computer.
    private func track(_ r: TurnReport) -> [String] {
        let shooter = r.shooter
        let target = 1 - shooter
        if let victim = r.damagedArcher { damageTakenThisRound[victim] += r.damage }
        let hitTarget = r.outcome.hitArcher == target
        hitStreak[shooter] = hitTarget ? hitStreak[shooter] + 1 : 0
        let firstShot = engine.state.suddenDeath == 0 && engine.state.shotsThisRound[shooter] == 1
        if shooter == me {
            if hitTarget {
                stats.hits += 1
                if r.outcome.hitPart == .head { stats.headshots += 1 }
                stats.longestHit = max(stats.longestHit, engine.state.conditions.distance)
                if firstShot { stats.firstTryHits += 1 }
            } else if let miss = r.missDistance {
                stats.closestMiss = min(stats.closestMiss ?? .infinity, miss)
            }
        }
        guard humans.contains(shooter) && hitTarget else { return [] }
        var medals: [String] = []
        if engine.state.conditions.distance >= 250 { medals.append("long shot") }
        if firstShot { medals.append("first try") }
        if hitStreak[shooter] >= 3 { medals.append("on fire") } else if hitStreak[shooter] == 2 { medals.append("2 in a row") }
        return medals
    }

    /// The arrow has landed: hide flight-only HUD.
    func impactBegan() {
        minimap = nil
        flightDistance = nil
    }

    /// Health bars update at the moment of impact.
    func applyHealth(_ h: [Int]) {
        withAnimation(.easeOut(duration: 0.5)) { health = h }
    }

    func updateFlight(path: [Vec2], index: Int, position: Vec2, heading: Double, distance: Double, shooter: Int) {
        let step = max(1, path.count / 90)
        var pts = stride(from: 0, to: path.count, by: step).map { CGPoint(x: path[$0].x, y: path[$0].y) }
        if let last = path.last { pts.append(CGPoint(x: last.x, y: last.y)) }
        let c = flightConditions ?? engine.state.conditions
        let feet = [c.archerPosition(0), c.archerPosition(1)].map { CGPoint(x: $0.x, y: $0.y) }
        let lo = min(feet[0].x, feet[1].x), hi = max(feet[0].x, feet[1].x)
        let extra = (hi - lo) * 0.2
        minimap = Minimap(path: pts, arrow: CGPoint(x: position.x, y: position.y), heading: CGFloat(heading),
                          flown: min(pts.count, index / step + 1), ground: [], archers: feet,
                          archerHeight: CGFloat(1.95 * config.game.physics.archerScale), shooter: shooter,
                          span: (lo - extra)...(hi + extra))
        flightDistance = Int(distance.rounded())
    }


    private func afterShot(_ report: TurnReport) {
        scene.updateConditions(engine.state.conditions)
        minimap = nil
        flightDistance = nil
        health = engine.state.health
        guard let event = report.events.last else { return }
        switch event {
        case .windChanged, .knockedBack:
            break // always followed by .nextTurn
        case .nextTurn:
            phase = .presenting
            planAIShotIfNeeded()
            // A wind drift is shown only by the indicator, the leaves and a light touch.
            if report.events.contains(where: { if case .windChanged = $0 { return true }; return false }) {
                updateWind()
                services.haptics.tap()
            }
            scene.panTo(shooter: engine.state.currentShooter) { [weak self] in self?.beginTurn() }
        case .suddenDeath:
            phase = .between
            showBanner(Banner(title: "SUDDEN DEATH", subtitle: "closest shot wins")) { [weak self] in
                self?.beginRound()
            }
        case .roundOver:
            phase = .between
            roundsWon = engine.state.roundsWon
            let you = engine.state.roundsWon[me], them = engine.state.roundsWon[1 - me]
            services.audio.play(.jingleRound)
            let winner = { if case let .roundOver(w, _) = event { return w }; return 0 }()
            if winner == me && damageTakenThisRound[me] == 0 { stats.cleanRounds += 1 }
            if mode == .passAndPlay || winner == me { services.haptics.roundWon() } else { services.haptics.roundLost() }
            let subtitle: String
            if mode == .passAndPlay {
                subtitle = "round to \(names[winner].lowercased())"
            } else {
                subtitle = winner == me ? (damageTakenThisRound[me] == 0 ? "flawless." : "round won") : "round lost"
            }
            showBanner(Banner(title: "\(you)–\(them)", subtitle: subtitle)) { [weak self] in
                guard let self else { return }
                self.engine.startNextRound()
                self.beginRound()
            }
        case let .matchOver(winner):
            roundsWon = engine.state.roundsWon
            phase = .over
            services.audio.play(winner == me || mode == .passAndPlay ? .jingleMatch : .jingleLose)
            if winner == me || mode == .passAndPlay { services.haptics.success() } else { services.haptics.roundLost() }
            scene.archers[winner].setExpression(.victorious)
            scene.archers[1 - winner].setExpression(.defeated)
            scene.run(.wait(forDuration: 1.6)) { [weak self] in self?.finish(forfeited: false) }
        }
    }

    private func showBanner(_ b: Banner, then: @escaping () -> Void) {
        services.haptics.bump()
        withAnimation(.spring(duration: 0.35)) { banner = b }
        scene.run(.wait(forDuration: 2.0)) { [weak self] in
            withAnimation(.easeIn(duration: 0.2)) { self?.banner = nil }
            then()
        }
    }

    /// Advanced by the scene every frame.
    func tick(dt: Double) {
        guard phase == .aiming, timeLeft != nil else { return }
        let t = (exactTimeLeft ?? timeLeft!) - dt
        exactTimeLeft = t
        if t <= 0 {
            timeLeft = nil
            exactTimeLeft = nil
            scene.autoShot()
        } else if Int(t * 10) != Int(timeLeft! * 10) {
            // Feel the last five seconds tick away.
            if t <= 5, Int(t.rounded(.up)) != Int(timeLeft!.rounded(.up)) {
                services.haptics.timerTick()
                if Int(t.rounded(.up)) == 5 {
                    scene.say(["any day now...", "zzz...", "today, please.", "I'm growing a beard here."],
                              by: 1 - engine.state.currentShooter, chance: 0.8, hold: 2.2)
                }
            }
            // Publish at 10 Hz; the ring doesn't need more.
            timeLeft = t
        }
    }

    private var exactTimeLeft: Double?

    func forfeit() {
        online?.duel.leave()
        engine.forfeit(by: engine.state.currentShooter == 1 && mode == .passAndPlay ? 1 : me)
        aiTask?.cancel()
        aiPlan?.cancel()
        finish(forfeited: true)
    }

    /// Leaves the match for the title screen. Against the computer it counts as
    /// a forfeit (your streak ends); pass and play just stops.
    /// A stray arrow got a chicken. Only the people playing get it on their record.
    func chickenDown(shooter: Int) {
        services.audio.play(.squawk, volume: 0.9)
        services.audio.play(.bonk, volume: 0.35)
        guard humans.contains(shooter) else { return }
        services.haptics.nearMiss()
        services.progress.recordChickenKilled()
    }

    func quitToTitle() {
        guard !finished else { return }
        finished = true
        aiTask?.cancel()
        aiPlan?.cancel()
        scene.isGamePaused = true
        online?.duel.leave()
        if mode != .passAndPlay {
            engine.forfeit(by: me)
            stats.won = false
            stats.forfeited = true
            _ = services.progress.record(stats, xp: services.config.xp)
        }
        services.analytics.log("match_end", ["mode": mode.analyticsName, "outcome": "quit", "forfeit": true])
    }

    private func finish(forfeited: Bool) {
        guard !finished else { return }
        finished = true
        let winner = engine.state.winner ?? (1 - me)
        let before = services.progress.totalXP
        var rewards: MatchRewards?
        if mode != .passAndPlay {
            stats.won = winner == me
            stats.forfeited = forfeited
            rewards = services.progress.record(stats, xp: services.config.xp)
        }
        services.analytics.log("match_end", [
            "mode": mode.analyticsName, "outcome": winner == me ? "win" : "loss",
            "rounds": engine.state.round, "durationS": Int(Date().timeIntervalSince(startedAt)), "forfeit": forfeited,
        ])
        onFinish?(MatchSummary(
            mode: mode, names: names, winner: winner, score: engine.state.roundsWon,
            arrowsLanded: engine.state.hitsLanded[winner], headshots: engine.state.headshots[me],
            xpBefore: before, rewards: rewards, forfeited: forfeited, me: me, avatars: avatars, hats: hats,
            opponentLeft: opponentLeft, health: engine.state.health
        ))
        online?.duel.close()
    }
}
