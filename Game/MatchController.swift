import LongbowCore
import SpriteKit
import SwiftUI

/// vs the computer (A7.1), or two people passing one phone.
enum MatchMode: Equatable {
    case vsAI(AIDifficulty)
    case passAndPlay

    var difficulty: AIDifficulty? {
        if case let .vsAI(d) = self { return d }
        return nil
    }
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

    var won: Bool { winner == 0 }
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
    let mode: MatchMode
    let difficulty: AIDifficulty
    /// Players controlled by touch.
    let humans: Set<Int>
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
        humans = mode == .passAndPlay ? [0, 1] : [0]
        var names = mode == .passAndPlay ? ["PLAYER 1", "PLAYER 2"] : ["YOU", "GUS"]
        #if DEBUG
        // `-playerName BraveYew_42` tests long gamertags in the HUD.
        if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-playerName"),
           i + 1 < ProcessInfo.processInfo.arguments.count {
            names[0] = ProcessInfo.processInfo.arguments[i + 1]
        }
        #endif
        self.names = names
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
        let setup = MatchSetup(seed: seed, arena: .hills, roundsToWin: game.rules.roundsToWin,
                               firstShooter: MatchSetup.tossWinner(seed: seed),
                               challenge: HitChallenge(rawValue: difficulty.rawValue) ?? .medium)
        engine = MatchEngine(setup: setup, config: game)
        ai = AIPlayer(difficulty: difficulty, seed: seed &+ 0xA1)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-autoplay") {
            autoplayAI = AIPlayer(difficulty: .hard, seed: seed &+ 0xB2)
        }
        #endif
        health = engine.state.health
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        scene = MatchScene(size: sceneSize, appConfig: config, reduceMotion: reduceMotion,
                           hats: [services.progress.equippedHat, mode == .passAndPlay ? .featherCap : .none],
                           avatars: [services.progress.avatar, .gus])
        scene.controller = self
    }

    var roundsToWin: Int { engine.state.setup.roundsToWin }
    var firstShooter: Int { engine.state.setup.firstShooter }
    var distance: Double { engine.state.conditions.distance }

    func start() {
        services.analytics.log("match_start", ["mode": mode == .passAndPlay ? "pass_and_play" : "ai",
                                               "difficulty": difficulty.rawValue, "arena": "hills"])
        services.audio.stopMusic()
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
        updateWind()
        let shooter = engine.state.currentShooter
        if humans.contains(shooter) && !(shooter == 0 && autoplayAI != nil) {
            phase = .aiming
            timeLeft = config.game.rules.shotTimeLimitSeconds
            exactTimeLeft = nil
            scene.beginHumanAim(shooter: shooter, lastBreath: engine.state.lastBreath, ghostShot: lastShot[shooter])
            // A protest is under way nearby: a flutter of wings, once a round.
            if scene.noticeProtester() { services.haptics.flutter() }
            if mode == .passAndPlay {
                withAnimation { turnNote = "\(names[shooter].lowercased()), you're up." }
                scene.run(.wait(forDuration: 2.2)) { [weak self] in withAnimation { self?.turnNote = nil } }
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
        guard engine.state.phase == .awaitingShot,
              !humans.contains(shooter) || (shooter == 0 && autoplayAI != nil) else { return }
        let engineCopy = engine
        var aiCopy = shooter == 1 ? ai : autoplayAI!
        aiPlan = Task.detached(priority: .userInitiated) {
            let shot = aiCopy.chooseShot(engine: engineCopy)
            return (shot, aiCopy)
        }
    }

    private func runAITurn(shooter: Int) {
        if aiPlan == nil { planAIShotIfNeeded() }
        let plan = aiPlan
        aiPlan = nil
        var thinker = shooter == 1 ? ai : autoplayAI!
        let think = thinker.thinkTime()
        aiTask = Task { [weak self] in
            let started = Date()
            guard let input = await plan?.value else { return }
            guard let self, !Task.isCancelled else { return }
            if shooter == 1 { self.ai = input.1 } else { self.autoplayAI = input.1 }
            let remaining = max(0.9, think + 0.9 - Date().timeIntervalSince(started))
            self.isAIDrawing = true
            self.scene.animateAIDraw(input.0, shooter: shooter, duration: remaining) { [weak self] in
                self?.isAIDrawing = false
                self?.submit(input.0)
            }
        }
    }

    /// Called by the scene when the player lets go.
    func humanReleased(_ input: ShotInput) {
        timeLeft = nil
        exactTimeLeft = nil
        submit(input)
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
        if shooter == 1 { ai.observe(report) } else { autoplayAI?.observe(report) }
        lastShot[shooter] = report.outcome
        let medals = track(report)
        services.analytics.log("shot_taken", [
            "mode": "ai", "round": report.round, "turn": report.turn,
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
        if shooter == 0 {
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
        minimap = Minimap(path: pts, arrow: CGPoint(x: position.x, y: position.y), heading: CGFloat(heading),
                          flown: min(pts.count, index / step + 1), ground: [], archers: feet,
                          archerHeight: CGFloat(1.95 * config.game.physics.archerScale), shooter: shooter)
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
            let you = engine.state.roundsWon[0], them = engine.state.roundsWon[1]
            services.audio.play(.jingleRound)
            let winner = { if case let .roundOver(w, _) = event { return w }; return 0 }()
            if winner == 0 && damageTakenThisRound[0] == 0 { stats.cleanRounds += 1 }
            if mode == .passAndPlay || winner == 0 { services.haptics.roundWon() } else { services.haptics.roundLost() }
            let subtitle: String
            if mode == .passAndPlay {
                subtitle = "round to \(names[winner].lowercased())"
            } else {
                subtitle = winner == 0 ? (damageTakenThisRound[0] == 0 ? "flawless." : "round won") : "round lost"
            }
            showBanner(Banner(title: "\(you)–\(them)", subtitle: subtitle)) { [weak self] in
                guard let self else { return }
                self.engine.startNextRound()
                self.beginRound()
            }
        case let .matchOver(winner):
            roundsWon = engine.state.roundsWon
            phase = .over
            services.audio.play(winner == 0 || mode == .passAndPlay ? .jingleMatch : .jingleLose)
            if winner == 0 || mode == .passAndPlay { services.haptics.success() } else { services.haptics.roundLost() }
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
        engine.forfeit(by: engine.state.currentShooter == 1 && mode == .passAndPlay ? 1 : 0)
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
        if mode != .passAndPlay {
            engine.forfeit(by: 0)
            stats.won = false
            stats.forfeited = true
            _ = services.progress.record(stats, xp: services.config.xp)
        }
        services.analytics.log("match_end", ["mode": mode == .passAndPlay ? "pass_and_play" : "ai",
                                             "outcome": "quit", "forfeit": true])
    }

    private func finish(forfeited: Bool) {
        guard !finished else { return }
        finished = true
        let winner = engine.state.winner ?? 1
        let before = services.progress.totalXP
        var rewards: MatchRewards?
        if mode != .passAndPlay {
            stats.won = winner == 0
            stats.forfeited = forfeited
            rewards = services.progress.record(stats, xp: services.config.xp)
        }
        services.analytics.log("match_end", [
            "mode": mode == .passAndPlay ? "pass_and_play" : "ai", "outcome": winner == 0 ? "win" : "loss",
            "rounds": engine.state.round, "durationS": Int(Date().timeIntervalSince(startedAt)), "forfeit": forfeited,
        ])
        onFinish?(MatchSummary(
            mode: mode, names: names, winner: winner, score: engine.state.roundsWon,
            arrowsLanded: engine.state.hitsLanded[winner], headshots: engine.state.headshots[0],
            xpBefore: before, rewards: rewards, forfeited: forfeited
        ))
    }
}
