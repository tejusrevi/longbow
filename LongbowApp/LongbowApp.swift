import ImageIO
import LongbowCore
import SwiftUI

@main
struct LongbowApp: App {
    @State private var services = Services.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.services, services)
                .environmentObject(services.settings)
                .environmentObject(services.progress)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .preferredColorScheme(.light)
                .onAppear {
                    services.analytics.log("app_open", ["isFirstLaunch": !UserDefaults.standard.bool(forKey: "launchedBefore")])
                    UserDefaults.standard.set(true, forKey: "launchedBefore")
                }
        }
    }
}

struct MatchRequest: Equatable {
    var mode: MatchMode
    var seed: UInt64 = .random(in: 1...UInt64.max)

    var names: [String] {
        switch mode {
        case .passAndPlay: return ["PLAYER 1", "PLAYER 2"]
        case .vsAI: return ["YOU", "GUS"]
        case let .online(o):
            var n = o.start.players.map(\.name)
            n[o.start.seat] = "YOU"
            return n
        }
    }
}

/// App routing. No tab bar: Home is the hub (spec A5).
enum Route: Equatable {
    case splash
    case home
    case online
    case toss(MatchRequest)
    case match(MatchRequest)
    case result(MatchSummary, MatchRequest)
}

struct RootView: View {
    @Environment(\.services) private var services
    @State private var route: Route = .splash
    @State private var autoplayMatches = 0

    #if DEBUG
    static let autoplay = ProcessInfo.processInfo.arguments.contains("-autoplay")
    /// Screenshot helper: `-screen editor|profile|toss|splash` opens that screen.
    static let debugScreen = UserDefaults.standard.string(forKey: "screen")
    #else
    static let autoplay = false
    static let debugScreen: String? = nil
    #endif

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            switch route {
            case .splash:
                SplashView {
                    switch Self.debugScreen {
                    case "splash": break
                    case "toss": go(.toss(MatchRequest(mode: .vsAI(.medium))))
                    case "online": go(.online)
                    default: go(Self.autoplay ? .toss(MatchRequest(mode: .vsAI(.medium))) : .home)
                    }
                }
            case .home:
                HomeView { mode in go(.toss(MatchRequest(mode: mode))) } onOnline: { go(.online) }
                    .transition(.opacity)
            case .online:
                OnlineView { match in
                    go(.toss(MatchRequest(mode: .online(match), seed: match.start.seed)))
                } onClose: { go(.home) }
                .transition(.opacity)
            case let .toss(request):
                tossView(request).transition(.opacity)
            case let .match(request):
                MatchView(request: request) { summary in go(.result(summary, request)) } onQuit: { go(.home) }
                    .transition(.opacity)
            case let .result(summary, request):
                MatchResultView(summary: summary) {
                    // An online rematch is a fresh duel from the lobby.
                    go(request.mode.isOnline ? .online : .toss(MatchRequest(mode: request.mode)))
                } onHome: {
                    go(.home)
                }
                .transition(.opacity)
                .task {
                    // DEBUG soak: keep playing matches back to back.
                    guard Self.autoplay, !request.mode.isOnline else { return }
                    autoplayMatches += 1
                    print("autoplay: finished match \(autoplayMatches), score \(summary.score)")
                    try? await Task.sleep(for: .seconds(2))
                    go(.toss(MatchRequest(mode: request.mode)))
                }
            }
        }
        .foregroundStyle(Color.ink)
        #if DEBUG
        .task {
            if let path = UserDefaults.standard.string(forKey: "renderIcon") { IconArt.write(to: path) }
            if let dir = UserDefaults.standard.string(forKey: "renderSheet") { SheetArt.write(to: dir) }
            if let dir = UserDefaults.standard.string(forKey: "renderLaunch") { BarnWall.writeLaunchImages(to: dir) }
        }
        #endif
        .overlay {
            switch Self.debugScreen {
            case "editor": AvatarEditor {}
            case "profile": ProfileSheet {}
            default: EmptyView()
            }
        }
    }

    @ViewBuilder
    private func tossView(_ request: MatchRequest) -> some View {
        if case let .online(o) = request.mode {
            TossView(seed: request.seed, opponent: .gus, names: request.names,
                     avatars: o.start.players.map(\.avatar), hats: o.start.players.map(\.hat),
                     winner: o.start.firstShooter) { go(.match(request)) }
        } else {
            TossView(seed: request.seed, opponent: .gus, names: request.names) { go(.match(request)) }
        }
    }

    private func go(_ r: Route) {
        // Duel music only while a match is on; the menu track everywhere else.
        switch r {
        case .match: break // the match starts its own track
        case .splash: break
        default: services.audio.playMusic(.menu)
        }
        withAnimation(.easeInOut(duration: 0.3)) { route = r }
    }
}

/// Launch splash (spec A5 #1). Someone left a camera in a barn. The title
/// is stuck on the lens; a chicken's head rises from under
/// the camera, right up close; its eyes dart about; it goes cross-eyed, leans
/// in ("?") and pecks the glass — crack. Then a slow blink. A feather
/// drifts down through all of it.
struct SplashView: View {
    let done: () -> Void
    @Environment(\.services) private var services
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stamped = false
    /// The title starts in the middle and moves up when the chicken arrives.
    @State private var labelUp = false
    @State private var rise: CGFloat = 0
    @State private var lean: CGFloat = 1
    @State private var gaze = CGPoint(x: 0, y: -0.2)
    @State private var crossed = false
    @State private var lid: CGFloat = 0
    @State private var puzzled = false
    @State private var cracked = false
    @State private var shake: CGFloat = 0
    @State private var feather: CGFloat = 0
    /// Head cock (degrees) and sideways shift: chickens look with their whole head.
    @State private var tilt: Double = -9
    @State private var shift: CGFloat = 0
    /// The big close-up takes a moment to draw; it's prepared in the
    /// background while the title stamps, and rises once it's ready.
    @State private var headReady = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                BarnWall().allowsHitTesting(false)

                // A feather, drifting down.
                InkArtImage(key: "splash.feather", bounds: ChickenArt.featherBounds, dotSpacing: 2) { ChickenArt.drawFeather(&$0) }
                    .frame(width: 70)
                    .rotationEffect(.degrees(-20 + 50 * sin(Double(feather) * 5)))
                    .position(x: w * (0.16 + 0.05 * sin(feather * 7)), y: -30 + feather * h * 0.75)

                // The head: right up against the lens, rising from below it.
                let headW = h * 1.35
                if headReady {
                LiveEyesChicken(key: "splash.closeup2", bounds: ChickenArt.closeBounds, eyes: ChickenArt.closeEyes,
                                gaze: gaze, crossed: crossed, lid: lid, pupilScale: 0.36, dotSpacing: 2.2) {
                    ChickenArt.drawCloseUp(&$0)
                }
                .frame(width: headW, height: headW * ChickenArt.closeBounds.height / ChickenArt.closeBounds.width)
                .scaleEffect(lean, anchor: UnitPoint(x: 0.5, y: 0.6))
                .rotationEffect(.degrees(tilt), anchor: UnitPoint(x: 0.5, y: 1))
                .position(x: w / 2 + shift, y: h * 0.72 + (1 - rise) * h * 1.25)
                .accessibilityHidden(true)
                }

                Text("?")
                    .font(Theme.hand(60))
                    .rotationEffect(.degrees(12))
                    .scaleEffect(puzzled ? 1 : 0.4)
                    .opacity(puzzled ? 1 : 0)
                    .position(x: w * 0.73, y: h * 0.36)

                // The title, stuck on the lens like a label.
                Wordmark(text: AppInfo.displayName.uppercased(), size: 54)
                    .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 4)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.paper))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.ink, lineWidth: 2.5))
                    .rotationEffect(.degrees(-2))
                    .scaleEffect(stamped ? 1 : 1.3)
                    .rotationEffect(.degrees(stamped ? 0 : -6))
                    .opacity(stamped ? 1 : 0)
                    .position(x: w / 2, y: labelUp ? h * 0.14 : h * 0.45)

                // The pecked lens.
                LensCrack()
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 130, height: 100)
                    .position(x: w * 0.52, y: h * 0.7)
                    .opacity(cracked ? 0.85 : 0)
                    .allowsHitTesting(false)
            }
            .offset(x: shake)
            .task {
                await PortraitCache.shared.prepareArt(key: "splash.closeup2", bounds: ChickenArt.closeBounds,
                                                      pointWidth: h * 1.35, scale: displayScale, dotSpacing: 2.2,
                                                      draw: ChickenArt.drawCloseUp)
                headReady = true
            }
        }
        .clipped()
        // Edge to edge: the chicken's neck runs under the home indicator.
        .ignoresSafeArea()
        .task {
            if reduceMotion {
                stamped = true; rise = 1; labelUp = true; tilt = 0
                try? await Task.sleep(for: .milliseconds(1000))
                return done()
            }
            let haptics = services.haptics
            func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) }
            /// Natural beats aren't metronomic: each pause wobbles a little.
            func beat(_ ms: Int) async { await wait(ms + Int.random(in: -25...25)) }
            // The feather tumbles: quick at first, then floats.
            withAnimation(.timingCurve(0.2, 0.6, 0.4, 1, duration: 2.8)) { feather = 1 }
            // The title stamps down in the middle.
            services.audio.play(.stamp, volume: 0.8)
            haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { stamped = true }
            await beat(280)
            while !headReady { await wait(16) }
            // Up comes a head, a touch too far, then settles; the title makes room.
            haptics.tap()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) { rise = 1; gaze = CGPoint(x: 0, y: 0.05) }
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.08)) { tilt = 3 }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) { labelUp = true }
            await beat(520)
            // Look left. Look right. A chicken's head jerks, then holds dead still.
            haptics.tap()
            withAnimation(.spring(response: 0.13, dampingFraction: 0.85)) {
                gaze = CGPoint(x: -0.75, y: -0.05); tilt = -7; shift = -8
            }
            await beat(190)
            haptics.tap()
            withAnimation(.spring(response: 0.13, dampingFraction: 0.85)) {
                gaze = CGPoint(x: 0.75, y: 0.03); tilt = 6; shift = 7
            }
            await beat(210)
            haptics.selection()
            // Cross-eyed at the lens, head cocked. Lean in. What is this thing?
            withAnimation(.spring(response: 0.14, dampingFraction: 0.8)) { gaze = .zero; crossed = true; shift = 0 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) { lean = 1.15; tilt = 11 }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5).delay(0.15)) { puzzled = true }
            await beat(300)
            // Rear back... and peck the lens.
            withAnimation(.easeOut(duration: 0.1)) { lean = 1.08; tilt = 4 }
            await wait(100)
            withAnimation(.easeIn(duration: 0.07)) { lean = 1.42; tilt = 0 }
            await wait(70)
            services.audio.play(.peck, volume: 0.9)
            haptics.thud()
            cracked = true
            withAnimation(.linear(duration: 0.04)) { shake = 5 }
            await wait(40)
            withAnimation(.linear(duration: 0.04)) { shake = -4 }
            await wait(40)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { shake = 0; puzzled = false; crossed = false }
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { lean = 1.05; tilt = -5 }
            await beat(200)
            // ...blink.
            withAnimation(.easeIn(duration: 0.08)) { lid = 1 }
            await wait(80)
            haptics.selection()
            withAnimation(.easeOut(duration: 0.15)) { lid = 0 }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { tilt = 2 }
            await wait(290)
            done()
        }
    }
}

/// Grey barn planks behind everything: wobbly seams, a few knots and grain.
/// Laid out from the screen centre in fixed points, so the launch screen
/// image (rendered from this same view, see `-renderLaunch`) lines up with it
/// on every iPhone.
struct BarnWall: View {
    static let plank: CGFloat = 148

    var body: some View {
        Canvas { ctx, size in
            let plank = Self.plank
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            var k = -Int((mid.x / plank).rounded(.up)) - 1
            while true {
                let x = mid.x + (CGFloat(k) + 0.35) * plank
                if x > size.width + plank { break }
                for dx in [0.0, 4.0] as [CGFloat] {
                    var p = Path()
                    var j = -Int((mid.y / 40).rounded(.up)) - 1
                    var y = mid.y + CGFloat(j) * 40
                    p.move(to: CGPoint(x: x + dx + sin(y * 0.05 + CGFloat(k)) * 1.6, y: y))
                    while y < size.height + 40 {
                        j += 1
                        y = mid.y + CGFloat(j) * 40
                        p.addLine(to: CGPoint(x: x + dx + sin(y * 0.05 + CGFloat(k)) * 1.6, y: y))
                    }
                    ctx.stroke(p, with: .color(Color.ink.opacity(dx == 0 ? 0.32 : 0.18)), lineWidth: dx == 0 ? 2.2 : 1.2)
                }
                // A knot and a little grain.
                let step = CGFloat(((k * 37) % 5 + 5) % 5) / 4
                let ky = mid.y + (0.18 + 0.23 * step - 0.5) * 400
                ctx.fill(Path(ellipseIn: CGRect(x: x + 14, y: ky, width: 7, height: 9)), with: .color(Color.ink.opacity(0.22)))
                var g = Path()
                g.move(to: CGPoint(x: x + plank * 0.55, y: ky + 30))
                g.addCurve(to: CGPoint(x: x + plank * 0.62, y: ky + 120),
                           control1: CGPoint(x: x + plank * 0.5, y: ky + 60), control2: CGPoint(x: x + plank * 0.66, y: ky + 90))
                ctx.stroke(g, with: .color(Color.ink.opacity(0.16)), lineWidth: 1.2)
                k += 1
            }
        }
    }

    #if DEBUG
    /// Writes the launch screen image at 1x/2x/3x into `dir`. It's larger than
    /// any iPhone in landscape; iOS centres it and crops the rest.
    @MainActor static func writeLaunchImages(to dir: String) {
        for scale in [1, 2, 3] {
            let view = BarnWall().frame(width: 1000, height: 480).background(Color.paper)
            let r = ImageRenderer(content: view)
            r.scale = CGFloat(scale)
            r.isOpaque = true
            guard let img = r.cgImage else { continue }
            let name = scale == 1 ? "launch_wall.png" : "launch_wall@\(scale)x.png"
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, img, nil)
            CGImageDestinationFinalize(dest)
        }
        print("launch images written to \(dir)")
    }
    #endif
}

/// A few hairline cracks radiating from where the beak hit the glass.
private struct LensCrack: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        let rays: [(CGFloat, CGFloat)] = [(0.2, 0.9), (1.3, 0.7), (2.2, 1.0), (3.4, 0.6), (4.4, 0.85), (5.4, 0.55)]
        for (a, len) in rays {
            var q = c
            p.move(to: q)
            for k in 1...3 {
                let t = CGFloat(k) / 3
                let jog: CGFloat = k % 2 == 0 ? 0.25 : -0.2
                q = CGPoint(x: c.x + cos(a + jog * 0.4) * r.width / 2 * len * t, y: c.y + sin(a + jog * 0.4) * r.height / 2 * len * t)
                p.addLine(to: q)
            }
        }
        p.addEllipse(in: CGRect(x: c.x - 5, y: c.y - 4, width: 10, height: 8))
        return p
    }
}

/// An ink chicken whose pupils and eyelids are live, so gazes and blinks
/// animate smoothly.
private struct LiveEyesChicken: View {
    let key: String
    let bounds: CGRect
    let eyes: [(center: CGPoint, radius: CGFloat)]
    /// Where the pupils point, in eye radii (x right, y down).
    let gaze: CGPoint
    /// Pupils drift toward the nose (looking at something very close).
    var crossed = false
    /// 0 = open, 1 = closed.
    let lid: CGFloat
    /// Pupil size as a share of the eye.
    var pupilScale: CGFloat = 0.46
    var dotSpacing: CGFloat = 2.4
    let draw: (inout InkCanvas) -> Void

    var body: some View {
        let b = bounds
        GeometryReader { geo in
            let k = geo.size.width / b.width
            ZStack(alignment: .topLeading) {
                InkArtImage(key: key, bounds: b, dotSpacing: dotSpacing, draw: draw)
                ForEach(0..<eyes.count, id: \.self) { i in
                    let e = eyes[i]
                    let d = e.radius * 2 * k
                    let pupil = d * (crossed ? pupilScale * 0.8 : pupilScale)
                    let inward: CGFloat = crossed ? (i == 0 ? 0.55 : -0.55) : 0
                    ZStack {
                        Circle().fill(Color.ink).frame(width: pupil, height: pupil)
                            .overlay(alignment: .topTrailing) {
                                // A glint of light.
                                Circle().fill(Color.paper).frame(width: pupil * 0.26, height: pupil * 0.26)
                                    .offset(x: -pupil * 0.12, y: pupil * 0.12)
                            }
                            .offset(x: (gaze.x + inward) * (d - pupil) / 2 * 0.85, y: gaze.y * (d - pupil) / 2 * 0.85)
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.paper).frame(height: d * lid)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color.ink).frame(height: max(1.5, d * 0.06)).opacity(lid > 0.05 ? 1 : 0)
                                }
                            Spacer(minLength: 0)
                        }
                    }
                    .frame(width: d * 0.9, height: d * 0.9)
                    .clipShape(Circle())
                    .position(x: (e.center.x - b.minX) * k, y: (b.maxY - e.center.y) * k)
                }
            }
        }
        .aspectRatio(b.width / b.height, contentMode: .fit)
    }
}
