import LongbowCore
import SwiftUI

/// Match result (spec A6.9): score, XP filling up (with level-ups), records
/// and streaks, and a new hat when you earn one. REMATCH is one tap away.
struct MatchResultView: View {
    let summary: MatchSummary
    let onRematch: () -> Void
    let onHome: () -> Void
    @Environment(\.services) private var services
    @EnvironmentObject private var progress: ProgressStore
    @State private var xpShown: Int = 0
    @State private var revealed = 0

    /// Score from this player's side.
    private var scoreText: String { "\(summary.score[summary.me])–\(summary.score[1 - summary.me])" }
    private var opponentName: String { summary.mode.isOnline ? summary.names[1 - summary.me].capitalized : "Gus" }

    private var title: String {
        if summary.mode == .passAndPlay { return "\(summary.names[summary.winner]) WINS" }
        if summary.forfeited { return "FORFEITED" }
        if summary.opponentLeft { return "THEY LEFT. YOU WIN" }
        return summary.won ? "YOU WIN" : "YOU LOSE"
    }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(title).font(Theme.display(24)).tracking(3)
                    Text(scoreText)
                        .font(Theme.display(min(118, geo.size.height * 0.24)))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .accessibilityLabel(Text("Score \(summary.score[summary.me]) to \(summary.score[1 - summary.me])"))
                    if let rewards = summary.rewards {
                        xpBar(rewards).frame(width: min(400, geo.size.width * 0.4))
                        rewardLines(rewards)
                    }
                    RewardedAdSlot(placement: .matchResult)
                    HStack(spacing: 14) {
                        Button("REMATCH", action: onRematch)
                            .buttonStyle(PillButtonStyle(primary: true))
                            .frame(width: 220)
                        IconButton(systemImage: "house", label: "Home", circle: true, action: onHome)
                        ShareLink(item: shareText) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18, weight: .bold))
                                .frame(width: 48, height: 48)
                                .background(Circle().strokeBorder(Color.ink, lineWidth: Theme.line))
                        }
                        .accessibilityLabel(Text("Share"))
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, 16)
                .frame(width: geo.size.width * 0.52, alignment: .leading)

                Group {
                    if let hat = summary.rewards?.unlockedHats.last {
                        hatUnlock(hat, size: min(geo.size.height * 0.5, geo.size.width * 0.24))
                    } else {
                        loserPortrait(size: min(geo.size.height * 0.56, geo.size.width * 0.27))
                    }
                }
                .frame(width: geo.size.width * 0.48)
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color.paper.ignoresSafeArea())
        .task { await reveal() }
    }

    private func reveal() async {
        xpShown = summary.xpBefore
        try? await Task.sleep(for: .milliseconds(350))
        if let r = summary.rewards {
            withAnimation(.easeOut(duration: 1.1)) { xpShown = summary.xpBefore + r.totalXP }
            for i in 1...(r.newRecords.count + 1) {
                try? await Task.sleep(for: .milliseconds(380))
                withAnimation(.spring(duration: 0.35)) { revealed = i }
                services.audio.play(.click, volume: 0.6)
                services.haptics.selection()
            }
            if r.levelAfter > r.levelBefore || !r.unlockedHats.isEmpty {
                services.audio.play(.jingleRound)
                services.haptics.success()
            }
        }
    }

    private var shareText: String {
        if summary.mode == .passAndPlay {
            return "\(summary.names[summary.winner]) won \(scoreText) in \(AppInfo.displayName)."
        }
        return summary.won
            ? "I beat \(opponentName) \(scoreText) in \(AppInfo.displayName)."
            : "\(opponentName) beat me \(summary.score[1 - summary.me])–\(summary.score[summary.me]) in \(AppInfo.displayName). Rematch."
    }

    private func xpBar(_ r: MatchRewards) -> some View {
        let info = ProgressStore.levelInfo(totalXP: xpShown)
        let leveledUp = info.level > r.levelBefore
        return VStack(spacing: 6) {
            HStack {
                Text("LVL \(info.level)").font(Theme.mono(14, bold: true))
                if leveledUp {
                    Text("level up!").font(Theme.hand(18)).transition(.scale.combined(with: .opacity))
                }
                Spacer()
                Text("+\(r.totalXP) xp").font(Theme.mono(14, bold: true))
            }
            InkProgressBar(fraction: Double(info.into) / Double(info.needed), height: 18)
        }
        .animation(.spring(duration: 0.4), value: leveledUp)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Level \(info.level), gained \(r.totalXP) XP"))
    }

    /// Records broken and streak, revealed one by one.
    @ViewBuilder
    private func rewardLines(_ r: MatchRewards) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(r.newRecords.enumerated()), id: \.offset) { i, rec in
                if revealed > i {
                    Text("new record — \(rec)").font(Theme.hand(17))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
            if revealed > r.newRecords.count && r.winStreak >= 2 {
                Text("\(r.winStreak) wins in a row.").font(Theme.hand(17)).transition(.opacity)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func loserPortrait(size: CGFloat) -> some View {
        let loser = 1 - summary.winner
        let loserIsGus = loser == 1
        let look: ArcherLook = loserIsGus ? .gus : .bjorn
        // Whoever lost, as they actually looked in the match.
        let face = summary.avatars.indices.contains(loser) ? summary.avatars[loser] : nil
        let hat = summary.mode.isOnline ? summary.hats[loser]
            : (look == .bjorn ? progress.equippedHat : (summary.mode == .passAndPlay ? .featherCap : .none))
        return ZStack {
            Circle()
                .fill(Color.clear)
                .overlay(DotPattern(spacing: 7, radius: 1.3).clipShape(Circle()))
                .frame(width: size * 1.25, height: size * 1.25)
            Circle().fill(Color.paper).frame(width: size, height: size)
            PortraitView(look: look, expression: .defeated, hat: hat, avatar: summary.mode.isOnline ? face : nil)
                .frame(width: size, height: size)
            // Every arrow the winner landed, stuck around the portrait.
            ForEach(0..<min(12, summary.arrowsLanded), id: \.self) { i in
                let angle = Double(i) * 137.5 + 30
                InkArtImage(key: "result.arrow", bounds: CharacterArt.arrowBounds) { CharacterArt.drawArrow(&$0) }
                    .frame(width: size * 0.42)
                    .rotationEffect(.degrees(180))
                    .offset(x: size * 0.42)
                    .rotationEffect(.degrees(angle))
            }
            // An apple that didn't make it, and a few loose feathers.
            InkArtImage(key: "result.apple", bounds: PropsArt.appleBounds) { PropsArt.drawApple(&$0, pierced: true) }
                .frame(width: size * 0.42)
                .rotationEffect(.degrees(-12))
                .offset(x: -size * 0.72, y: size * 0.52)
            ForEach(0..<2, id: \.self) { i in
                InkArtImage(key: "result.feather", bounds: PropsArt.featherBounds) { PropsArt.drawFeather(&$0) }
                    .frame(width: size * 0.22)
                    .rotationEffect(.degrees(i == 0 ? 25 : -40))
                    .offset(x: i == 0 ? size * 0.72 : -size * 0.68, y: i == 0 ? -size * 0.5 : -size * 0.35)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(summary.mode.isOnline || !loserIsGus ? summary.names[loser] : "Gus"), with \(summary.arrowsLanded) arrows landed"))
    }

    private func hatUnlock(_ hat: Hat, size: CGFloat) -> some View {
        let wearing = progress.equippedHat == hat
        return VStack(spacing: 12) {
            Text("NEW HAT!").font(Theme.display(26))
            ZStack {
                Circle().fill(Color.clear)
                    .overlay(DotPattern(spacing: 7, radius: 1.3).clipShape(Circle()))
                    .frame(width: size * 1.2, height: size * 1.2)
                PortraitView(look: .bjorn, expression: .victorious, hat: hat)
                    .frame(width: size, height: size)
            }
            Text(hat.title.lowercased()).font(Theme.hand(22))
            Button(wearing ? "WEARING IT" : "WEAR IT") {
                progress.equippedHat = hat
                services.haptics.selection()
                services.analytics.log("hat_equipped", ["hatId": hat.rawValue, "source": "unlock"])
            }
            .buttonStyle(PillButtonStyle(primary: !wearing))
            .frame(width: 200)
        }
        .onAppear { services.analytics.log("hat_unlocked", ["hatId": hat.rawValue, "source": "level"]) }
    }
}
