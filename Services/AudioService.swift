import AVFoundation

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

    init(settings: SettingsStore) {
        self.settings = settings
        // Ambient: mixes with other audio and respects the silent switch.
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        try? AVAudioSession.sharedInstance().setActive(true)
        for effect in SoundEffect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { continue }
            players[effect] = (0..<3).compactMap { _ in
                let p = try? AVAudioPlayer(contentsOf: url)
                p?.prepareToPlay()
                return p
            }
        }
    }

    func play(_ effect: SoundEffect, volume: Float) {
        guard settings.soundOn, let pool = players[effect] else { return }
        let player = pool.first { !$0.isPlaying } ?? pool[0]
        player.currentTime = 0
        player.volume = volume
        player.play()
    }

    /// The menu loop is supplied separately as `menu_music.m4a` (or .mp3/.wav).
    func startMusic() {
        guard settings.musicOn else { return }
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
