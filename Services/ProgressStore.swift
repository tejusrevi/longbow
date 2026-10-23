import Foundation
import LongbowCore

/// What one vs-AI match contributed, from the human's side.
struct MatchStats: Codable, Equatable {
    var won: Bool
    var difficulty: AIDifficulty
    var hits = 0
    var headshots = 0
    /// Distance between the archers on the longest round in which you landed a hit.
    var longestHit: Double = 0
    /// Hits on the first shot of a round.
    var firstTryHits = 0
    /// Rounds won without taking any damage.
    var cleanRounds = 0
    /// Closest miss on the target, in metres.
    var closestMiss: Double?
    var forfeited = false
}

struct LifetimeStats: Codable, Equatable {
    var matches = 0
    var wins = 0
    var winStreak = 0
    var bestStreak = 0
    var headshots = 0
    var longestHit: Double = 0
    var hardWins = 0
    /// Chickens hit by your stray arrows. Means nothing. Matters a lot.
    var chickensKilled = 0

    init() {}

    // Tolerant decoding, so stats saved before a field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        matches = try c.decodeIfPresent(Int.self, forKey: .matches) ?? 0
        wins = try c.decodeIfPresent(Int.self, forKey: .wins) ?? 0
        winStreak = try c.decodeIfPresent(Int.self, forKey: .winStreak) ?? 0
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        headshots = try c.decodeIfPresent(Int.self, forKey: .headshots) ?? 0
        longestHit = try c.decodeIfPresent(Double.self, forKey: .longestHit) ?? 0
        hardWins = try c.decodeIfPresent(Int.self, forKey: .hardWins) ?? 0
        chickensKilled = try c.decodeIfPresent(Int.self, forKey: .chickensKilled) ?? 0
    }
}

/// What the result screen celebrates.
struct MatchRewards: Equatable {
    var baseXP: Int
    var levelBefore: Int
    var levelAfter: Int
    var unlockedHats: [Hat]
    var newRecords: [String]
    var winStreak: Int

    var totalXP: Int { baseXP }
}

/// Local progression: XP and level (A12.1), hats (A14), streaks and records.
/// Deliberately no daily chores: you play because it's fun, and hats turn up
/// along the way. Server-backed in Milestone 3; on the device until then.
final class ProgressStore: ObservableObject {
    private let defaults: UserDefaults
    @Published private(set) var totalXP: Int
    @Published private(set) var stats: LifetimeStats
    @Published var equippedHat: Hat {
        didSet { defaults.set(equippedHat.rawValue, forKey: "equippedHat") }
    }
    /// Your face (A14a). Changing it is always free.
    @Published var avatar: Avatar {
        didSet { save(avatar, "avatar") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        totalXP = defaults.integer(forKey: "totalXP")
        stats = Self.load(LifetimeStats.self, "lifetimeStats", defaults) ?? LifetimeStats()
        equippedHat = Hat(rawValue: defaults.string(forKey: "equippedHat") ?? "") ?? .none
        avatar = Self.load(Avatar.self, "avatar", defaults) ?? .bjorn
        // Everyone starts bare-headed; a hat you haven't earned comes off.
        if !isUnlocked(equippedHat) { equippedHat = .none }
    }

    // MARK: Levels

    /// XP needed to go from `level` to `level + 1`: 100 + 40 × (level − 1).
    static func xpToNext(_ level: Int) -> Int { 100 + 40 * (level - 1) }

    static func levelInfo(totalXP: Int) -> (level: Int, into: Int, needed: Int) {
        var level = 1
        var rest = totalXP
        while rest >= xpToNext(level) {
            rest -= xpToNext(level)
            level += 1
        }
        return (level, rest, xpToNext(level))
    }

    var level: Int { Self.levelInfo(totalXP: totalXP).level }

    // MARK: Hats

    func isUnlocked(_ hat: Hat) -> Bool {
        switch hat.unlock {
        case let .level(l): return level >= l
        case let .beatHardGus(t): return stats.hardWins >= t
        }
    }

    func recordChickenKilled() {
        stats.chickensKilled += 1
        save(stats, "lifetimeStats")
    }

    // MARK: Recording a match

    func record(_ s: MatchStats, xp: XPConfig) -> MatchRewards {
        let before = level
        let hatsBefore = Set(Hat.allCases.filter(isUnlocked))
        var records: [String] = []

        // Lifetime stats and streaks.
        stats.matches += 1
        stats.headshots += s.headshots
        if s.won {
            stats.wins += 1
            stats.winStreak += 1
            if s.difficulty == .hard { stats.hardWins += 1 }
            if stats.winStreak > stats.bestStreak && stats.winStreak >= 2 {
                stats.bestStreak = stats.winStreak
                records.append("best streak: \(stats.bestStreak)")
            }
        } else {
            stats.winStreak = 0
        }
        if s.longestHit > stats.longestHit && s.longestHit > 0 {
            if stats.longestHit > 0 { records.append("longest hit: \(Int(s.longestHit)) m") }
            stats.longestHit = s.longestHit
        }

        // Base XP (A12.1) plus a little for every hit, so every match moves the bar.
        var base = s.forfeited ? 0 : xp.matchCompleted
        if s.won { base += xp.matchWon }
        base += s.headshots * xp.headshot + s.hits * 2

        totalXP += base

        defaults.set(totalXP, forKey: "totalXP")
        save(stats, "lifetimeStats")

        let unlocked = Hat.allCases.filter { isUnlocked($0) && !hatsBefore.contains($0) }
        return MatchRewards(baseXP: base, levelBefore: before, levelAfter: level,
                            unlockedHats: unlocked, newRecords: records, winStreak: stats.winStreak)
    }

    // MARK: Persistence

    /// Back to a brand-new player (the account was deleted).
    func resetAll() {
        for key in ["totalXP", "lifetimeStats", "equippedHat", "avatar"] { defaults.removeObject(forKey: key) }
        totalXP = 0
        stats = LifetimeStats()
        equippedHat = .none
        avatar = .bjorn
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String, _ d: UserDefaults) -> T? {
        guard let data = d.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
