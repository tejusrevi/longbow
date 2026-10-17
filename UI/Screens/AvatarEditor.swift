import LongbowCore
import SwiftUI

/// "Make your archer": the face editor (spec A14a.3).
///
/// Design:
/// - One question at a time: pick a tab, then pick from big options that each
///   show *your own* face with that change applied. The pictures are the
///   labels (VoiceOver still reads each option's name).
/// - Every tab is visible at once (two rows), so nothing hides off-screen.
/// - "Start from" offers a varied, mixed crowd of ready-made people; every
///   one of them is made from the same parts you can pick.
/// - Plain-word buttons (Shuffle, Undo) instead of cryptic icons.
/// - Lays out inside the safe area on every iPhone.
/// - Tiger (the cat) can be picked but not edited: try, and Tiger knocks your
///   option off the table.
struct AvatarEditor: View {
    let onClose: () -> Void
    @EnvironmentObject private var progress: ProgressStore
    @Environment(\.services) private var services
    @State private var draft: Avatar = .bjorn
    @State private var tab: Tab = .start
    @State private var history: [Avatar] = []
    @State private var confirmDiscard = false
    /// Option tiles Tiger has swatted off the screen (per tab).
    @State private var knocked: Set<Int> = []
    @State private var swats = 0
    @State private var quip: String?

    enum Tab: String, CaseIterable, Identifiable {
        case start, face, hair, brows, eyes, nose, mouth, beard, glasses, extras, outfit
        var id: String { rawValue }
        var title: String { self == .start ? "START FROM" : rawValue.uppercased() }

        /// What each tab's tiles zoom in on, so small differences read.
        enum Crop { case face, eyes, lowerFace, bust, hair
            var rect: CGRect? {
                switch self {
                case .face: return nil
                case .eyes: return CGRect(x: -0.14, y: 1.48, width: 0.46, height: 0.46)
                case .lowerFace: return CGRect(x: -0.13, y: 1.3, width: 0.5, height: 0.5)
                case .bust: return CGRect(x: -0.4, y: 0.86, width: 0.8, height: 0.8)
                case .hair: return CGRect(x: -0.46, y: 1.18, width: 0.96, height: 0.96)
                }
            }
        }

        var crop: Crop {
            switch self {
            case .brows, .eyes: return .eyes
            case .nose, .mouth: return .lowerFace
            case .outfit: return .bust
            case .hair: return .hair
            default: return .face
            }
        }

        var part: Avatar.Part? {
            switch self {
            case .start, .face: return nil
            case .hair: return .hair
            case .brows: return .brows
            case .eyes: return .eyes
            case .nose: return .nose
            case .mouth: return .mouth
            case .beard: return .facialHair
            case .glasses: return .glasses
            case .extras: return .accessory
            case .outfit: return .outfit
            }
        }
    }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                header
                HStack(alignment: .top, spacing: 20) {
                    previewColumn
                    VStack(alignment: .leading, spacing: 12) {
                        tabs
                        options
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .onAppear {
            draft = progress.avatar
            #if DEBUG
            if let t = UserDefaults.standard.string(forKey: "tab"), let tt = Tab(rawValue: t) { tab = tt }
            if let name = UserDefaults.standard.string(forKey: "preset"),
               let p = Avatar.presets.first(where: { $0.0 == name }) { draft = p.1 }
            #endif
            services.analytics.log("avatar_editor_opened")
        }
        .overlay {
            if confirmDiscard {
                InkAlert(title: "DISCARD CHANGES?", message: "Your archer goes back to how they were.",
                         primary: "KEEP EDITING", secondary: "DISCARD",
                         onPrimary: { confirmDiscard = false }, onSecondary: onClose)
            }
        }
        .onChange(of: tab) { knocked = []; quip = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            BackButton {
                if draft != progress.avatar { confirmDiscard = true } else { onClose() }
            }
            Text("MAKE YOUR ARCHER").font(Theme.display(22)).accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                services.analytics.log("avatar_saved", ["changed": draft != progress.avatar])
                progress.avatar = draft
                services.haptics.success()
                onClose()
            } label: {
                Text("DONE")
                    .font(Theme.display(16)).tracking(2)
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, 26)
                    .frame(height: 44)
                    .background(Capsule().fill(Color.ink))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Preview

    private var previewColumn: some View {
        VStack(spacing: 12) {
            PortraitView(look: .bjorn, expression: .neutral, avatar: draft)
                .frame(width: 168, height: 168)
                // Tiger swats back when you try to edit.
                .rotationEffect(.degrees(swats % 2 == 0 ? 0 : (swats % 4 == 1 ? -9 : 9)))
                .animation(.spring(response: 0.18, dampingFraction: 0.35), value: swats)
                .accessibilityLabel(Text("Your archer"))
            HStack(spacing: 10) {
                smallButton("SHUFFLE") { change { $0 = .random() } }
                smallButton("UNDO") {
                    guard let last = history.popLast() else { return }
                    draft = last
                    services.haptics.selection()
                }
                .opacity(history.isEmpty ? 0.35 : 1)
                .disabled(history.isEmpty)
            }
        }
        .frame(width: 180)
    }

    private func smallButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.mono(13))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(Capsule().strokeBorder(Color.ink, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Tabs (all visible, two rows)

    private var tabs: some View {
        let rows = [Array(Tab.allCases.prefix(6)), Array(Tab.allCases.dropFirst(6))]
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(0..<2, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r]) { t in
                        Button {
                            tab = t
                            services.haptics.selection()
                        } label: {
                            Text(t.title)
                                .font(Theme.mono(12, bold: tab == t))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(tab == t ? Color.paper : Color.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background(Capsule().fill(tab == t ? Color.ink : Color.paper))
                                .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(tab == t ? .isSelected : [])
                    }
                }
            }
        }
    }

    // MARK: Options

    @ViewBuilder
    private var options: some View {
        if tab == .start {
            optionStrip(count: Avatar.presets.count, tileHeight: Self.tile) { i in
                let (name, face) = Avatar.presets[i]
                return tile(face: face, label: name.lowercased(), showLabel: true, selected: draft == face) {
                    change { $0 = face }
                }
            }
        } else if draft.tiger {
            tigerRefuses
        } else if tab == .face {
            VStack(alignment: .leading, spacing: 10) {
                optionStrip(count: Avatar.Part.head.count, rows: 1, tileHeight: Self.tile) { i in
                    var f = draft; f.head = i
                    return tile(face: f, label: Avatar.Part.head.optionName(i), selected: draft.head == i) {
                        change { $0.head = i }
                    }
                }
                HStack(spacing: 12) {
                    ForEach(0..<Avatar.Part.skin.count, id: \.self) { i in skinSwatch(i) }
                    Rectangle().fill(Color.ink.opacity(0.25)).frame(width: 2, height: 40).padding(.horizontal, 4)
                    ForEach(0..<Avatar.Part.hairTone.count, id: \.self) { i in hairSwatch(i) }
                }
            }
        } else {
            let part = tab.part!
            optionStrip(count: part.count, tileHeight: Self.tile) { i in
                var f = draft; f[part] = i
                // Show mouths even under a walrus moustache or a gum bubble.
                if part == .mouth {
                    if f.facialHair == 3 { f.facialHair = 0 }
                    if f.accessory == 10 { f.accessory = 0 }
                }
                return tile(face: f, label: part.optionName(i), selected: draft[part] == i, crop: tab.crop) {
                    change { $0[part] = i }
                }
            }
        }
    }

    private static let tile: CGFloat = 92

    /// Tiger can't be edited. The options are there, but tapping one makes
    /// Tiger knock it off the table, like a cat does.
    private var tigerRefuses: some View {
        let part = tab.part ?? .head
        let quips = ["Tiger knocked it off the table.", "Tiger is perfect as is.", "Tiger is ignoring you.",
                     "*hiss*", "Tiger sat on that one.", "Tiger would like dinner instead.",
                     "Tiger does not do makeovers.", "Tiger has filed a complaint."]
        return VStack(alignment: .leading, spacing: 6) {
            Text(quip ?? "Tiger doesn’t do makeovers. Pick someone else.")
                .font(Theme.hand(18))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .id(quip)
                .transition(.opacity)
            optionStrip(count: part.count, rows: 1, tileHeight: Self.tile) { i in
                var f = Avatar(); f[part] = i
                return tile(face: f, label: part.optionName(i), selected: false) {
                    guard !knocked.contains(i) else { return }
                    withAnimation(.easeIn(duration: 0.55)) { _ = knocked.insert(i) }
                    swats += 1 // swat...
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { swats += 1 } // ...and settle
                    withAnimation { quip = quips[(swats / 2 + i) % quips.count] }
                    services.haptics.nearMiss()
                    services.analytics.log("tiger_refused")
                }
                .offset(y: knocked.contains(i) ? 420 : 0)
                .rotationEffect(.degrees(knocked.contains(i) ? Double(40 + (i * 37) % 60) : 0))
                .opacity(knocked.contains(i) ? 0 : 0.55)
            }
        }
    }

    /// Options in a horizontally scrolling strip (two rows by default).
    private func optionStrip<Tile: View>(count: Int, rows: Int = 2, tileHeight: CGFloat,
                                         @ViewBuilder tile: @escaping (Int) -> Tile) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(tileHeight), spacing: 8), count: rows), spacing: 8) {
                ForEach(0..<count, id: \.self) { i in tile(i) }
            }
            .padding(.vertical, 2)
            .padding(.trailing, 12)
        }
        .frame(height: CGFloat(rows) * tileHeight + CGFloat(rows - 1) * 8 + 4)
    }

    /// A big face tile. Only "Start from" shows names; for parts the picture
    /// says it all (VoiceOver still reads the name).
    private func tile(face: Avatar, label: String, showLabel: Bool = false, selected: Bool, crop: Tab.Crop = .face,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                PortraitView(look: .bjorn, avatar: face, faceOnly: crop == .face, crop: crop.rect)
                    .frame(width: showLabel ? 68 : 82, height: showLabel ? 68 : 82)
                if showLabel {
                    Text(label)
                        .font(Theme.mono(11, bold: selected))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Color.paper : Color.ink)
                }
            }
            .frame(width: Self.tile - (showLabel ? 4 : 0), height: Self.tile)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? Color.ink : Color.paper))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ink, lineWidth: selected ? 3.5 : 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Skin as halftone density swatches — the game is black and white, so
    /// tone is shown as more or fewer dots, never as a colour.
    private func skinSwatch(_ i: Int) -> some View {
        let selected = draft.skin == i
        return Button { change { $0.skin = i } } label: {
            InkArtImage(key: "skin.swatch.\(i)", bounds: CGRect(x: -0.55, y: -0.55, width: 1.1, height: 1.1)) { c in
                c.circle(.zero, 0.5, fill: AvatarArt.skinPaint(i), width: 0.06, count: 14)
            }
            .frame(width: 46, height: 46)
            .padding(4)
            .overlay(Circle().strokeBorder(Color.ink, lineWidth: selected ? 3.5 : 0).padding(-2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Skin tone: \(Avatar.Part.skin.optionName(i))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Hair colour as a little lock of hair in that tone.
    private func hairSwatch(_ i: Int) -> some View {
        let selected = draft.hairTone == i
        return Button { change { $0.hairTone = i } } label: {
            InkArtImage(key: "hair.swatch.\(i)", bounds: CGRect(x: -0.55, y: -0.55, width: 1.1, height: 1.1), dotSpacing: 2) { c in
                let pts = [CGPoint(x: -0.1, y: 0.5), CGPoint(x: 0.35, y: 0.3), CGPoint(x: 0.25, y: -0.1), CGPoint(x: 0.4, y: -0.5),
                           CGPoint(x: -0.05, y: -0.25), CGPoint(x: -0.4, y: -0.45), CGPoint(x: -0.3, y: 0.05)]
                _ = c.mass(pts, paint: AvatarArt.hairTonePaint(i))
                c.brushLoop(pts, width: 0.05)
            }
            .frame(width: 42, height: 42)
            .padding(6)
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ink, lineWidth: selected ? 3.5 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Hair colour: \(Avatar.Part.hairTone.optionName(i))"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func change(_ edit: (inout Avatar) -> Void) {
        var next = draft
        edit(&next)
        guard next != draft else { return }
        history.append(draft)
        if history.count > 20 { history.removeFirst() }
        draft = next
        services.haptics.selection()
    }
}
