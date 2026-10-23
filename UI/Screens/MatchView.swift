import LongbowCore
import SpriteKit
import SwiftUI

/// In-match screen: the SpriteKit scene plus the quiet SwiftUI HUD
/// (`Aim`, `Flight`, `Hit`, `Miss` mockups).
struct MatchView: View {
    let request: MatchRequest
    let onFinish: (MatchSummary) -> Void
    let onQuit: () -> Void
    @Environment(\.services) private var services
    @StateObject private var holder = ControllerHolder()

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            if let controller = holder.controller {
                SpriteView(scene: controller.scene, preferredFramesPerSecond: 120,
                           options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
                    .accessibilityLabel(Text("Battlefield. Drag back anywhere and let go to shoot."))
                // The HUD stays inside the safe area, clear of the rounded corners
                // and the Dynamic Island.
                MatchHUD(controller: controller, onQuit: onQuit)
            }
        }
        .onAppear {
            guard holder.controller == nil else { return }
            let c = MatchController(mode: request.mode, seed: request.seed, services: services,
                                    sceneSize: UIScreen.main.bounds.size)
            c.onFinish = onFinish
            holder.controller = c
            c.start()
        }
    }
}

@MainActor
private final class ControllerHolder: ObservableObject {
    @Published var controller: MatchController?
}

/// The match HUD. Design rule: only what's needed right now, kept to the edges
/// and out of the way of the archers and the arrow's landing area.
private struct MatchHUD: View {
    @ObservedObject var controller: MatchController
    let onQuit: () -> Void
    @Environment(\.services) private var services

    var body: some View {
        ZStack {
            // Top: name plates and wind while aiming; a slim mini-map in flight.
            VStack {
                if let map = controller.minimap {
                    HStack(spacing: 12) {
                        MiniMap(map: map)
                        if let d = controller.flightDistance {
                            Text("\(d) m")
                                .font(Theme.mono(14, bold: true))
                                .monospacedDigit()
                                .frame(width: 64, alignment: .leading)
                        }
                    }
                    .padding(.top, 6)
                    .transition(.opacity)
                } else {
                    topBar.transition(.opacity)
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.3), value: controller.minimap == nil)

            // Bottom-left: pause (with the shot timer ring) while aiming.
            // Pause (and the way back to the title) is always there, bottom-left.
            if controller.phase != .over && controller.banner == nil {
                PauseButton(timeLeft: controller.phase == .aiming ? controller.timeLeft : nil,
                            limit: services.config.game.rules.shotTimeLimitSeconds) {
                    services.haptics.selection()
                    controller.paused = true
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .transition(.opacity)
            }

            if let banner = controller.banner {
                VStack(spacing: 2) {
                    Text(banner.title).font(Theme.display(76)).monospacedDigit()
                    if let s = banner.subtitle { Text(s).font(Theme.mono(21)) }
                }
                .padding(.horizontal, 60).padding(.vertical, 30)
                .background(Ellipse().fill(Color.paper).blur(radius: 24).opacity(0.92))
                .transition(.scale(scale: 0.85).combined(with: .opacity))
                .accessibilityElement(children: .combine)
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.2), value: controller.phase)
        .overlay {
            if controller.paused {
                PauseMenu(controller: controller, onQuit: onQuit)
            }
        }
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: 16) {
            PlayerPlate(name: controller.names[0], country: controller.countries[0], health: controller.health[0],
                        roundsWon: controller.roundsWon[0], roundsToWin: controller.roundsToWin, trailing: false)
            Spacer(minLength: 8)
            VStack(spacing: 6) {
                WindIndicator(wind: controller.windWorld)
                if let note = controller.turnNote {
                    Text(note).font(Theme.mono(14)).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            Spacer(minLength: 8)
            PlayerPlate(name: controller.names[1], country: controller.countries[1], health: controller.health[1],
                        roundsWon: controller.roundsWon[1], roundsToWin: controller.roundsToWin, trailing: true)
        }
    }
}

/// Name above a thin health bar, with round pips beside the name. Names get the
/// full bar width (16-character gamertags fit) and shrink rather than clip.
private struct PlayerPlate: View {
    let name: String
    let country: String
    let health: Int
    let roundsWon: Int
    let roundsToWin: Int
    let trailing: Bool

    var body: some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 5) {
            HStack(spacing: 8) {
                // One-round matches have nothing to count.
                if trailing && roundsToWin > 1 { RoundPips(won: roundsWon, of: roundsToWin) }
                Text(name)
                    .font(Theme.mono(15, bold: true, relativeTo: .headline))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .layoutPriority(1)
                if !country.isEmpty {
                    Text(country).font(Theme.mono(11, bold: true)).opacity(0.6).accessibilityLabel(Text(Countries.name(country)))
                }
                if !trailing && roundsToWin > 1 { RoundPips(won: roundsWon, of: roundsToWin) }
            }
            .frame(width: 184, alignment: trailing ? .trailing : .leading)
            HealthBar(value: health, mirrored: trailing, height: 14)
                .frame(width: 184)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rounds won, as small dots under the health bar.
private struct RoundPips: View {
    let won: Int
    let of: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<of, id: \.self) { i in
                Circle()
                    .fill(i < won ? Color.ink : Color.paper)
                    .overlay(Circle().strokeBorder(Color.ink, lineWidth: 1.5))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(won) rounds won"))
    }
}

/// A small, quiet windsock: the flag points where it blows, and the number is
/// the strength (spec A6.6). No label, no announcement — it just eases to the
/// new wind when it drifts.
private struct WindIndicator: View {
    let wind: Double

    var body: some View {
        let strength = abs(wind)
        let right = wind >= 0
        HStack(spacing: 5) {
            FlagShape()
                .fill(Color.ink)
                .frame(width: 20, height: 14)
                .scaleEffect(x: right ? 1 : -1)
                .opacity(strength == 0 ? 0.3 : 1)
            Text(strength == 0 ? "calm" : String(format: strength.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.1f", strength))
                .font(Theme.mono(12, bold: true))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(Capsule().fill(Color.paper.opacity(0.85)))
        .opacity(0.8)
        .animation(.easeInOut(duration: 0.6), value: wind)
        .accessibilityElement()
        .accessibilityLabel(Text(wind == 0 ? "No wind" : "Wind \(strength, specifier: "%.1f") blowing \(right ? "right" : "left")"))
    }
}

private struct FlagShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        // Pole on the left, flag waving to the right.
        p.addRoundedRect(in: CGRect(x: r.minX, y: r.minY, width: 3.5, height: r.height), cornerSize: CGSize(width: 1.5, height: 1.5))
        p.move(to: CGPoint(x: r.minX + 3, y: r.minY + 2))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.18),
                   control1: CGPoint(x: r.minX + r.width * 0.4, y: r.minY - 2),
                   control2: CGPoint(x: r.minX + r.width * 0.6, y: r.minY + r.height * 0.32))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.12, y: r.minY + r.height * 0.36))
        p.addCurve(to: CGPoint(x: r.minX + 3, y: r.minY + r.height * 0.5),
                   control1: CGPoint(x: r.minX + r.width * 0.6, y: r.minY + r.height * 0.56),
                   control2: CGPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.3))
        p.closeSubpath()
        return p
    }
}

private struct PauseButton: View {
    let timeLeft: Double?
    let limit: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.paper)
                Circle().strokeBorder(Color.ink, lineWidth: 2.5)
                Image(systemName: "pause.fill").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.ink)
                // Ring shows the time left from 5 s (spec A6.11).
                if let t = timeLeft, t <= 5 {
                    Circle()
                        .trim(from: 0, to: max(0, t / 5))
                        .stroke(Color.ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .padding(-7)
                        .animation(.linear(duration: 0.1), value: t)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Pause"))
        .accessibilityValue(Text(timeLeft.map { "\(Int($0.rounded(.up))) seconds left" } ?? ""))
    }
}

/// Thin mini-map during flight: the two archers at the two ends of the line,
/// the path flown so far and the arrow. Distance and height share one scale,
/// so the arc's shape and angles match the real shot; the strip is as tall as
/// this flight needs (squeezed to two thirds). Everything is fixed for the whole flight.
private struct MiniMap: View {
    let map: MatchController.Minimap
    static let width: CGFloat = 260
    static let inset: CGFloat = 7

    /// One scale for the flight: the line runs 20% past both archers.
    private var span: (left: CGFloat, right: CGFloat, base: CGFloat, k: CGFloat) {
        let left = map.span.lowerBound, right = map.span.upperBound
        let base = map.archers.map(\.y).min() ?? 0
        return (left, right, base, (Self.width - 2 * Self.inset) / max(right - left, 1))
    }

    /// The part of the flight over the strip; the rest is clipped off.
    private var visiblePath: [CGPoint] {
        let on = map.path.filter { map.span.contains($0.x) }
        return on.isEmpty ? map.path : on
    }

    /// Sized to this flight's arc over the strip (and any dip below the
    /// archers), kept to a narrow strip: two thirds of the true-scale height.
    var height: CGFloat {
        let sp = span, vis = visiblePath
        let top = max((vis.map(\.y).max() ?? sp.base) - sp.base, 0)
        let dip = max(sp.base - (vis.map(\.y).min() ?? sp.base), 0)
        return min(53, max(20, ((top + dip) * sp.k + 2 * Self.inset) * 2 / 3))
    }

    var body: some View {
        Canvas { ctx, size in
            let sp = span, vis = visiblePath
            let top = max((vis.map(\.y).max() ?? sp.base) - sp.base, 0)
            let dip = max(sp.base - (vis.map(\.y).min() ?? sp.base), 0)
            // Very high lobs are the only case squeezed a little to fit.
            let ky = min(sp.k, (size.height - 2 * Self.inset) / max(top + dip, 0.01))
            let baseY = Self.inset + top * ky
            func pt(_ p: CGPoint) -> CGPoint {
                CGPoint(x: Self.inset + (p.x - sp.left) * sp.k, y: baseY - (p.y - sp.base) * ky)
            }
            // The strip's two ends, 20% past each archer.
            let x0 = Self.inset, x1 = size.width - Self.inset

            var line = Path()
            line.move(to: CGPoint(x: x0, y: baseY))
            line.addLine(to: CGPoint(x: x1, y: baseY))
            ctx.stroke(line, with: .color(.ink), lineWidth: 2)

            // The flight and the arrow vanish where they leave the strip.
            let strip = Path(CGRect(x: x0, y: -20, width: x1 - x0, height: size.height + 40))
            ctx.drawLayer { ctx in
                ctx.clip(to: strip)
                var flown = Path()
                for (i, p) in map.path.prefix(map.flown).enumerated() { i == 0 ? flown.move(to: pt(p)) : flown.addLine(to: pt(p)) }
                flown.addLine(to: pt(map.arrow))
                ctx.stroke(flown, with: .color(.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }

            for (i, f) in map.archers.enumerated() {
                let c = CGPoint(x: pt(f).x, y: baseY)
                let r = CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)
                if i == map.shooter {
                    ctx.fill(Path(ellipseIn: r), with: .color(.ink))
                } else {
                    ctx.fill(Path(ellipseIn: r), with: .color(.paper))
                    ctx.stroke(Path(ellipseIn: r), with: .color(.ink), lineWidth: 2)
                }
            }
            ctx.drawLayer { ctx in
                ctx.clip(to: strip)
                let a = pt(map.arrow)
                ctx.fill(Path(ellipseIn: CGRect(x: a.x - 6, y: a.y - 6, width: 12, height: 12)), with: .color(.ink))
            }
        }
        .frame(width: Self.width, height: height)
        .accessibilityHidden(true)
    }
}

/// Pause menu: Resume, Sound on/off, Forfeit with confirmation (spec A5).
private struct PauseMenu: View {
    @ObservedObject var controller: MatchController
    let onQuit: () -> Void
    @EnvironmentObject private var settings: SettingsStore
    @State private var confirmQuit = false

    var body: some View {
        ZStack {
            // Bleeds past the HUD padding and the safe area; the buttons don't.
            Color.paper.opacity(0.94).padding(-60).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(confirmQuit ? "QUIT?" : "PAUSED").font(Theme.display(40))
                if confirmQuit {
                    Text(controller.mode == .passAndPlay ? "This match ends here." : "Back to the title. Counts as a loss.")
                        .font(Theme.mono(15))
                    HStack(spacing: 14) {
                        Button("STAY") { confirmQuit = false }
                            .buttonStyle(PillButtonStyle(primary: true))
                        Button("QUIT") {
                            controller.quitToTitle()
                            onQuit()
                        }
                        .buttonStyle(PillButtonStyle(primary: false))
                    }
                } else {
                    Button("RESUME") { controller.paused = false }
                        .buttonStyle(PillButtonStyle(primary: true))
                    HStack(spacing: 14) {
                        Button(settings.soundOn ? "SOUND: ON" : "SOUND: OFF") { settings.soundOn.toggle() }
                            .buttonStyle(PillButtonStyle(primary: false))
                        Button("QUIT") { confirmQuit = true }
                            .buttonStyle(PillButtonStyle(primary: false))
                    }
                }
            }
            .frame(maxWidth: 560)
            .padding(32)
        }
    }
}
