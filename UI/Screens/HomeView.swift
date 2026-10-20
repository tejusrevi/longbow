import LongbowCore
import SpriteKit
import SwiftUI

/// Title / home (spec A5). Left: the wordmark and the two ways to play.
/// Right: a William Tell scene. Top-right: your archer and level (tap for
/// hats and records).
struct HomeView: View {
    let onPlay: (MatchMode) -> Void
    @Environment(\.services) private var services
    @EnvironmentObject private var progress: ProgressStore
    @State private var scene: HomeScene?
    @State private var sheet: Sheet?
    @AppStorage("coachMarkShown") private var coachMarkShown = false
    @AppStorage("profileOpened") private var profileOpened = false

    enum Sheet: Equatable { case difficulty, multiplayer, profile, onlineSoon }

    var body: some View {
        ZStack {
            // The illustration runs edge to edge, behind everything.
            if let scene {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }

            // Controls stay inside the safe area: clear of the notch / Dynamic
            // Island on whichever side it is, and of the home indicator.
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Wordmark(text: AppInfo.displayName.uppercased(), size: min(80, geo.size.width * 0.095))
                            .padding(.bottom, 4)
                        HandUnderline()
                            .stroke(Color.ink, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                            .frame(width: min(300, geo.size.width * 0.32), height: 8)
                            .padding(.bottom, 24)

                        VStack(spacing: 14) {
                            Button("SINGLE PLAYER") { open(.difficulty) }
                                .buttonStyle(PillButtonStyle(primary: true))
                            Button("MULTI PLAYER") { open(.multiplayer) }
                                .buttonStyle(PillButtonStyle(primary: false))
                        }
                        .frame(width: min(320, geo.size.width * 0.4))

                        ShopEntrySlot()
                        SeasonTrackSlot()
                    }
                    .padding(.leading, 12)
                    .padding(.top, geo.size.height * 0.1)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            }

            // Your archer, top right, the same distance from the top and the
            // right edge of the screen.
            ProfileChip(showHint: !profileOpened) { profileOpened = true; open(.profile) }
                .padding(.top, 18)
                .padding(.trailing, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .ignoresSafeArea()

            if let sheet {
                Group {
                    switch sheet {
                    case .difficulty:
                        DifficultySheet(onPick: { d in self.sheet = nil; onPlay(.vsAI(d)) },
                                        onClose: { self.sheet = nil })
                    case .multiplayer:
                        MultiplayerSheet(onPassAndPlay: { self.sheet = nil; onPlay(.passAndPlay) },
                                         onOnline: { self.sheet = .onlineSoon },
                                         onClose: { self.sheet = nil })
                    case .profile:
                        ProfileSheet { self.sheet = nil }
                    case .onlineSoon:
                        NoticeCard(title: "ONLINE", message: "Friend duels and quick match arrive in the next build.") {
                            self.sheet = .multiplayer
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: sheet)
        .onAppear {
            if scene == nil {
                let s = HomeScene(size: CGSize(width: 500, height: 400), boil: !UIAccessibility.isReduceMotionEnabled,
                                  hat: progress.equippedHat, avatar: progress.avatar)
                let haptics = services.haptics
                s.onChickenPoked = { haptics.flutter() }
                scene = s
            }
            services.audio.startMusic()
        }
        .task { await ArtLibrary.shared.prewarm(avatar: progress.avatar, hat: progress.equippedHat) }
        .onChange(of: progress.equippedHat) { _, hat in scene?.setHat(hat) }
        .onChange(of: progress.avatar) { _, face in scene?.setAvatar(face) }
    }

    private func open(_ s: Sheet) {
        services.haptics.selection()
        services.audio.play(.click)
        coachMarkShown = true
        sheet = s
    }
}

/// Top-right: your archer in their hat, level and XP, on a raised "sticker"
/// card so it reads as a button. Until you've opened it once, a hand-written
/// note points at it.
private struct ProfileChip: View {
    let showHint: Bool
    let action: () -> Void
    @EnvironmentObject private var progress: ProgressStore
    @State private var wiggle = false

    var body: some View {
        let info = ProgressStore.levelInfo(totalXP: progress.totalXP)
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 5) {
                    HStack(spacing: 8) {
                        if progress.stats.winStreak >= 2 {
                            Text("\(progress.stats.winStreak) in a row").font(Theme.hand(14))
                        }
                        Text("LVL \(info.level)").font(Theme.display(16))
                    }
                    InkProgressBar(fraction: Double(info.into) / Double(info.needed), height: 9)
                        .frame(width: 96)
                }
                PortraitView(look: .bjorn, hat: progress.equippedHat)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(wiggle ? -8 : 0), anchor: .bottom)
            }
            .padding(.leading, 16)
            .padding(.trailing, 5)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.paper))
            .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2.5))
            .background(Capsule().fill(Color.ink).offset(x: 3, y: 4))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if showHint {
                // Tucked under the chip on the right, clear of the scenery.
                VStack(alignment: .trailing, spacing: 0) {
                    HintArrow()
                        .stroke(Color.ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 26, height: 30)
                        .rotationEffect(.degrees(-35))
                        .padding(.trailing, 22)
                    Text("that's you!\ntap to dress up")
                        .font(Theme.hand(16))
                        .multilineTextAlignment(.trailing)
                }
                .rotationEffect(.degrees(-3))
                .fixedSize()
                .offset(x: -6, y: 74)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .task {
            // One small wave hello, then it keeps still.
            guard showHint else { return }
            try? await Task.sleep(for: .seconds(1.2))
            for _ in 0..<2 {
                withAnimation(.easeInOut(duration: 0.15)) { wiggle = true }
                try? await Task.sleep(for: .milliseconds(160))
                withAnimation(.easeInOut(duration: 0.15)) { wiggle = false }
                try? await Task.sleep(for: .milliseconds(160))
            }
        }
        .accessibilityLabel(Text("Profile, level \(info.level)"))
    }
}

/// A hand-drawn curved arrow pointing up and to the right.
private struct HintArrow: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let tip = CGPoint(x: r.maxX - 3, y: r.minY + 3)
        p.move(to: CGPoint(x: r.minX + 2, y: r.maxY - 4))
        p.addQuadCurve(to: tip, control: CGPoint(x: r.midX + 6, y: r.maxY))
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - 11, y: tip.y + 2))
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - 1, y: tip.y + 11))
        return p
    }
}

/// Mode select: vs AI difficulty (spec A5 #4).
struct DifficultySheet: View {
    let onPick: (AIDifficulty) -> Void
    let onClose: () -> Void
    @Environment(\.services) private var services

    var body: some View {
        ZStack {
            Color.paper.opacity(0.94).ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    BackButton(action: onClose)
                    Text("VS GUS").font(Theme.display(34)).accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 14) {
                    ForEach(AIDifficulty.allCases, id: \.self) { d in
                        Button {
                            services.haptics.selection()
                            services.audio.play(.click)
                            onPick(d)
                        } label: {
                            VStack(spacing: 4) {
                                Text(d.title)
                                Text(d.blurb(config: services.config.game.rules))
                                    .font(Theme.mono(12, relativeTo: .caption))
                                    .tracking(0)
                            }
                        }
                        .buttonStyle(PillButtonStyle(primary: d == .medium))
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 720)
        }
    }
}

/// Multi player: pass and play on one phone now; online in Milestone 2.
private struct MultiplayerSheet: View {
    let onPassAndPlay: () -> Void
    let onOnline: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.paper.opacity(0.94).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    BackButton(action: onClose)
                    Text("MULTI PLAYER").font(Theme.display(34)).accessibilityAddTraits(.isHeader)
                }
                HStack(spacing: 14) {
                    Button(action: onPassAndPlay) {
                        VStack(spacing: 4) {
                            Text("PASS & PLAY")
                            Text("one phone, take turns").font(Theme.mono(12)).tracking(0)
                        }
                    }
                    .buttonStyle(PillButtonStyle(primary: true))
                    Button(action: onOnline) {
                        VStack(spacing: 4) {
                            Text("ONLINE")
                            Text("soon").font(Theme.mono(12)).tracking(0)
                        }
                    }
                    .buttonStyle(PillButtonStyle(primary: false))
                    .opacity(0.55)
                }
            }
            .padding(32)
            .frame(maxWidth: 640)
        }
    }
}

extension AIDifficulty {
    var title: String {
        switch self {
        case .easy: return "EASY"
        case .medium: return "MEDIUM"
        case .hard: return "HARD"
        }
    }

    /// What makes each hit harder at this level.
    func blurb(config: RulesConfig) -> String {
        switch self {
        case .easy: return "light wind · small stagger"
        case .medium: return "wind · hits knock back"
        case .hard: return "strong wind · big knockback · no aim guide"
        }
    }
}

struct NoticeCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.paper.opacity(0.94).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(spacing: 16) {
                Text(title).font(Theme.display(30))
                Text(message).font(Theme.mono(15)).multilineTextAlignment(.center)
                Button("OK", action: onClose)
                    .buttonStyle(PillButtonStyle(primary: true))
                    .frame(width: 200)
            }
            .padding(32)
            .frame(maxWidth: 460)
        }
    }
}
