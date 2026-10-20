import AVFoundation
import os
import UIKit

/// Sound effects and music (spec A15).
enum SoundEffect: String, CaseIterable {
    case creak1 = "creak_1", creak2 = "creak_2", creak3 = "creak_3"
    case creak4 = "creak_4", creak5 = "creak_5", creak6 = "creak_6"
    case twang, whoosh
    case thunkDirt = "thunk_dirt", thunkWood = "thunk_wood"
    case thwack, grunt, bonk, clang
    case ooh
    case tossSpin = "toss_spin", tossClick = "toss_click"
    case jingleRound = "jingle_round", jingleMatch = "jingle_match", jingleLose = "jingle_lose"
    case click
    case squawk

    /// Bowstring creak for a draw power 0...1 (pitch rises with power).
    static func creak(power: Double) -> SoundEffect {
        let all: [SoundEffect] = [.creak1, .creak2, .creak3, .creak4, .creak5, .creak6]
        return all[min(all.count - 1, max(0, Int(power * Double(all.count))))]
    }
}

protocol AudioService: AnyObject {
    func play(_ effect: SoundEffect, volume: Float)
    func startMusic()
    func stopMusic()
}

extension AudioService {
    func play(_ effect: SoundEffect) { play(effect, volume: 1) }
}

final class DeviceAudioService: AudioService {
    private let settings: SettingsStore
    private var players: [SoundEffect: [AVAudioPlayer]] = [:]
    private var music: AVAudioPlayer?
    private var sessionActive = false
    private let log = Logger(subsystem: "com.tejusrevi.longbow", category: "audio")

    init(settings: SettingsStore) {
        self.settings = settings
        activateSession()
        for effect in SoundEffect.allCases { players[effect] = makePlayers(effect) }
        let center = NotificationCenter.default
        // Calls, Siri, alarms or another app can take the audio away; take it
        // back when they're done, and whenever the game comes to the front.
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            let type = (n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            if type == .began { self?.sessionActive = false } else { self?.activateSession() }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sessionActive = false
            self.activateSession()
            for effect in SoundEffect.allCases { self.players[effect] = self.makePlayers(effect) }
            self.music = nil
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.sessionActive = false
            self?.activateSession()
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

    private func makePlayers(_ effect: SoundEffect) -> [AVAudioPlayer] {
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else {
            log.error("missing sound \(effect.rawValue, privacy: .public)")
            return []
        }
        return (0..<3).compactMap { _ in
            do {
                let p = try AVAudioPlayer(contentsOf: url)
                p.prepareToPlay()
                return p
            } catch {
                log.error("sound \(effect.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
    }

    func play(_ effect: SoundEffect, volume: Float) {
        guard settings.soundOn else { return }
        activateSession()
        if players[effect]?.isEmpty ?? true { players[effect] = makePlayers(effect) }
        guard let pool = players[effect], !pool.isEmpty else { return }
        let player = pool.first { !$0.isPlaying } ?? pool[0]
        player.currentTime = 0
        player.volume = volume
        if !player.play() {
            // A player can go stale after the session was lost: rebuild and retry once.
            sessionActive = false
            activateSession()
            players[effect] = makePlayers(effect)
            if let fresh = players[effect]?.first {
                fresh.volume = volume
                if !fresh.play() { log.error("could not play \(effect.rawValue, privacy: .public)") }
            }
        }
    }

    /// The menu loop is supplied separately as `menu_music.m4a` (or .mp3/.wav).
    func startMusic() {
        guard settings.musicOn else { return }
        activateSession()
        if music == nil {
            let url = ["m4a", "mp3", "wav", "caf"].lazy
                .compactMap { Bundle.main.url(forResource: "menu_music", withExtension: $0) }.first
            guard let url, let p = try? AVAudioPlayer(contentsOf: url) else { return }
            p.numberOfLoops = -1
            p.volume = 0.5
            music = p
        }
        music?.play()
    }

    func stopMusic() {
        music?.pause()
    }
}
