import LongbowCore
import SpriteKit
import SwiftUI

/// Toss (spec A6.9): who shoots first? The chicken decides — it looks from one
/// archer to the other, has a think, then dashes over to the first shooter.
/// The result comes from the match seed. Tap anywhere to skip.
struct TossView: View {
    let seed: UInt64
    let opponent: ArcherLook
    var names: [String] = ["YOU", "GUS"]
    /// Who stands on each side (defaults: you vs Gus).
    var avatars: [Avatar]? = nil
    var hats: [Hat]? = nil
    /// Online, the server's toss decides; offline it's worked out from the seed.
    var winner: Int? = nil
    let onDone: () -> Void
    @EnvironmentObject private var progress: ProgressStore
    @Environment(\.services) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scene: TossScene?
    @State private var decided = false
    @State private var finished = false

    private var tossWinner: Int { winner ?? MatchSetup.tossWinner(seed: seed) }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.paper
                if let scene {
                    SpriteView(scene: scene, options: [.allowsTransparency])
                        .accessibilityHidden(true)
                }
                // Names over each archer (they stand at ±archerX of the view).
                let f = TossScene.archerX / TossScene.viewWidth
                ForEach(0..<2, id: \.self) { i in
                    nameTag(i)
                        .position(x: geo.size.width * (0.5 + (i == 0 ? -f : f)), y: geo.size.height * 0.2)
                }
                VStack(spacing: 2) {
                    Text(decided ? headline : "who shoots first?")
                        .font(decided ? Theme.display(30) : Theme.mono(21))
                        .contentTransition(.opacity)
                    Text(decided ? "the chicken has spoken." : "the chicken decides.")
                        .font(Theme.mono(14))
                        .opacity(0.8)
                }
                .multilineTextAlignment(.center)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.16)
                .animation(.spring(duration: 0.35), value: decided)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
            }
            .onAppear { makeScene(size: geo.size) }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .accessibilityAction(named: Text("Skip")) { finish() }
    }

    private var headline: String {
        names[tossWinner] == "YOU" ? "you shoot first!" : "\(names[tossWinner].lowercased()) shoots first!"
    }

    private func nameTag(_ i: Int) -> some View {
        let picked = decided && tossWinner == i
        return Text(names[i])
            .font(Theme.display(22))
            .foregroundStyle(picked ? Color.paper : Color.ink)
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(Capsule().fill(picked ? Color.ink : Color.paper))
            .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2.5))
            .scaleEffect(picked ? 1.12 : 1)
            .rotationEffect(.degrees(picked ? (i == 0 ? -4 : 4) : 0))
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: picked)
    }

    private func makeScene(size: CGSize) {
        guard scene == nil else { return }
        let hats: [Hat] = self.hats ?? [progress.equippedHat, names[1] == "GUS" ? .none : .featherCap]
        let avatars: [Avatar] = self.avatars ?? [progress.avatar, .gus]
        let s = TossScene(size: size, boil: !reduceMotion, fast: reduceMotion, avatars: avatars, hats: hats,
                          winner: tossWinner)
        s.onLook = {
            services.audio.play(.cluck, volume: 0.5)
            services.haptics.selection()
        }
        s.onDecided = {
            services.audio.play(.tossClick)
            services.haptics.bump()
            decided = true
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                finish()
            }
        }
        scene = s
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        decided = true
        onDone()
    }
}
