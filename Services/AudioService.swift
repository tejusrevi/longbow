import AVFoundation
import os
import UIKit

/// Sound effects and music (spec A15).
enum SoundEffect: String, CaseIterable {
    case ratchet1 = "ratchet_1", ratchet2 = "ratchet_2", ratchet3 = "ratchet_3"
    case ratchet4 = "ratchet_4", ratchet5 = "ratchet_5", ratchet6 = "ratchet_6"
    case twang, whoosh
    case thunkDirt = "thunk_dirt", thunkWood = "thunk_wood"
    case thwack, grunt, bonk, clang
    case ooh
    case tossSpin = "toss_spin", tossClick = "toss_click"
    case jingleRound = "jingle_round", jingleMatch = "jingle_match", jingleLose = "jingle_lose"
    case click
    case squawk
    case cluck, cackle, stamp, peck, scuff, gust

    /// Recorded takes of this sound: a play picks one, never the same twice in
    /// a row, so repeated actions don't sound like a loop.
    var variants: [String] {
        switch self {
        case .twang, .thwack, .grunt, .thunkDirt, .cluck: return [rawValue, rawValue + "_2", rawValue + "_3"]
        case .whoosh, .click: return [rawValue, rawValue + "_2"]
        default: return [rawValue]
        }
    }

    /// Small random pitch shift per play (bow, hits and chickens; never jingles).
    var pitchJitter: Float {
        switch self {
        case .twang, .whoosh, .thwack, .thunkDirt, .thunkWood, .grunt, .bonk, .cluck, .squawk, .scuff, .peck: return 0.06
        case .click: return 0.04
        default: return 0
        }
    }

    /// Ratchet click for a draw power 0...1 (pitch rises with power).
    static func ratchet(power: Double) -> SoundEffect {
        let all: [SoundEffect] = [.ratchet1, .ratchet2, .ratchet3, .ratchet4, .ratchet5, .ratchet6]
        return all[min(all.count - 1, max(0, Int(power * Double(all.count))))]
    }
}

/// The two music beds you supply (drop the files in Resources/Music/).
enum MusicTrack: String {
    /// Title, lobby, toss and results.
    case menu = "menu_music"
    /// During a duel.
    case duel = "duel_music"
}

protocol AudioService: AnyObject {
    func play(_ effect: SoundEffect, volume: Float)
    /// Crossfades to `track` (no-op if it's already playing or the file is missing).
    func playMusic(_ track: MusicTrack)
    func stopMusic()
}

extension AudioService {
    func play(_ effect: SoundEffect) { play(effect, volume: 1) }
    func startMusic() { playMusic(.menu) }
}

final class DeviceAudioService: AudioService {
    private let settings: SettingsStore
    /// Three players per take, so overlapping plays don't cut each other off.
    private var players: [String: [AVAudioPlayer]] = [:]
    private var lastVariant: [SoundEffect: String] = [:]
    private var music: [MusicTrack: AVAudioPlayer] = [:]
    private var currentTrack: MusicTrack?
    private var sessionActive = false
    private let log = Logger(subsystem: "com.tejusrevi.longbow", category: "audio")
    private static let musicVolume: Float = 0.5

    init(settings: SettingsStore) {
        self.settings = settings
        // Loading ~50 takes blocks for a second or more, so it happens in the
        // background while the splash plays. A sound asked for before then is
        // loaded on the spot by play().
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let session = AVAudioSession.sharedInstance()
            let active = (try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])) != nil
                && (try? session.setActive(true)) != nil
            var loaded: [String: [AVAudioPlayer]] = [:]
            for effect in SoundEffect.allCases { for name in effect.variants { loaded[name] = self.makePlayers(name) } }
            DispatchQueue.main.async {
                if active { self.sessionActive = true }
                self.players.merge(loaded) { current, _ in current }
            }
        }
        let center = NotificationCenter.default
        // Calls, Siri, alarms or another app can take the audio away; take it
        // back when they're done, and whenever the game comes to the front.
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            if type == .began { self?.sessionActive = false } else { self?.activateSession(); self?.resumeMusic() }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sessionActive = false
            self.activateSession()
            for effect in SoundEffect.allCases { for name in effect.variants { self.players[name] = self.makePlayers(name) } }
            self.music.removeAll()
            if let t = self.currentTrack { self.currentTrack = nil; self.playMusic(t) }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = false
            self?.activateSession()
            self?.resumeMusic()
        }
    }

    /// Playback, so sounds play even with the ringer on silent (the in-game
    /// Sound toggle is the way to mute), mixed with whatever music you have on.
    private func activateSession() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            sessionActive = true
        } catch {
            log.error("audio session failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makePlayers(_ name: String) -> [AVAudioPlayer] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else {
            log.error("missing sound \(name, privacy: .public)")
            return []
        }
        return (0..<3).compactMap { _ in
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.enableRate = true
                p.prepareToPlay()
                return p
            } catch {
                log.error("sound \(name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    private func pickVariant(_ effect: SoundEffect) -> String {
        let all = effect.variants
        guard all.count > 1 else { return all[0] }
        let pick = all.filter { $0 != lastVariant[effect] }.randomElement() ?? all[0]
        lastVariant[effect] = pick
        return pick
    }

    func play(_ effect: SoundEffect, volume: Float) {
        guard settings.soundOn else { return }
        activateSession()
        let name = pickVariant(effect)
        if players[name]?.isEmpty ?? true { players[name] = makePlayers(name) }
        guard let pool = players[name], !pool.isEmpty else { return }
        let player = pool.first { !$0.isPlaying } ?? pool[0]
        player.currentTime = 0
        player.volume = volume
        let j = effect.pitchJitter
        player.rate = j > 0 ? Float.random(in: (1 - j)...(1 + j)) : 1
        if !player.play() {
            // A player can go stale after the session was lost: rebuild and retry once.
            sessionActive = false
            activateSession()
            players[name] = makePlayers(name)
            if let fresh = players[name]?.first {
                fresh.volume = volume
                if !fresh.play() { log.error("could not play \(name, privacy: .public)") }
            }
        }
    }

    // MARK: Music

    /// Looks for Resources/Music/<track>.m4a (or .mp3/.wav/.caf).
    private func musicPlayer(_ track: MusicTrack) -> AVAudioPlayer? {
        if let p = music[track] { return p }
        let url = ["m4a", "mp3", "wav", "caf", "aac"].lazy
            .compactMap { Bundle.main.url(forResource: track.rawValue, withExtension: $0) }.first
        guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return nil }
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        music[track] = p
        return p
    }

    func playMusic(_ track: MusicTrack) {
        guard currentTrack != track else { return resumeMusic() }
        let previous = currentTrack.flatMap { music[$0] }
        currentTrack = track
        previous?.setVolume(0, fadeDuration: 0.8)
        if let previous { DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { if previous.volume == 0 { previous.pause() } } }
        guard settings.musicOn else { return }
        activateSession()
        guard let next = musicPlayer(track) else { return }
        next.currentTime = 0
        next.volume = 0
        next.play()
        next.setVolume(Self.musicVolume, fadeDuration: 1.0)
    }

    private func resumeMusic() {
        guard settings.musicOn, let t = currentTrack, let p = musicPlayer(t), !p.isPlaying else { return }
        p.play()
        p.setVolume(Self.musicVolume, fadeDuration: 0.6)
    }

    func stopMusic() {
        for p in music.values { p.setVolume(0, fadeDuration: 0.5) }
        currentTrack = nil
    }
}
