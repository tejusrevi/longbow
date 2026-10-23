import LongbowCore
import SwiftUI

/// You at a glance (A14). Laid out to fit one landscape screen on the
/// smallest iPhone, inside the safe area:
/// - Left, your archer card: portrait, a big EDIT ARCHER button, and level.
/// - Right, your records as a row of number cards (chickens included),
///   then the hat rack in one scrolling row.
struct ProfileSheet: View {
    let onClose: () -> Void
    @EnvironmentObject private var progress: ProgressStore
    @Environment(\.services) private var services
    @State private var editingFace = false
    @State private var editingTag = false
    @State private var confirmDelete = false
    @State private var deleteProblem: String?

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 16) {
                    BackButton(action: onClose)
                    Text("YOU").font(Theme.display(30)).accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 26) {
                    archerCard
                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("RECORDS")
                        records
                        sectionLabel("HATS").padding(.top, 6)
                        hatRack
                    }
                }
                Spacer(minLength: 0)
                accountRow
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 8)
            if confirmDelete {
                InkAlert(title: "DELETE ACCOUNT?",
                         message: "Your gamertag, level, records and hats are gone for good. This can't be undone.",
                         primary: "KEEP IT", secondary: "DELETE",
                         onPrimary: { confirmDelete = false },
                         onSecondary: deleteAccount)
            }
        }
        // Full screen, so it always lays out inside the safe area.
        .fullScreenCover(isPresented: $editingFace) {
            AvatarEditor { editingFace = false }
                .environmentObject(progress)
                .environment(\.services, services)
        }
        .fullScreenCover(isPresented: $editingTag) {
            GamertagSheet(onDone: { editingTag = false }, onCancel: { editingTag = false }, account: services.account)
                .environment(\.services, services)
        }
    }

    // MARK: Account

    private var accountRow: some View {
        AccountRow(account: services.account, problem: deleteProblem,
                   onChange: { editingTag = true },
                   onDelete: {
                       services.haptics.selection()
                       confirmDelete = true
                   })
    }

    private func deleteAccount() {
        confirmDelete = false
        Task {
            do {
                try await services.account.deleteAccount(progress: progress)
                services.haptics.success()
                services.analytics.log("account_deleted", [:])
                onClose()
            } catch {
                deleteProblem = "Couldn't reach the server, so nothing was deleted. Try again?"
            }
        }
    }

    // MARK: Archer card

    private var archerCard: some View {
        let info = ProgressStore.levelInfo(totalXP: progress.totalXP)
        return VStack(spacing: 10) {
            Button(action: edit) {
                PortraitView(look: .bjorn, hat: progress.equippedHat)
                    .frame(width: 132, height: 132)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            Button(action: edit) {
                HStack(spacing: 8) {
                    Image(systemName: "pencil").font(.system(size: 15, weight: .heavy))
                    Text("EDIT ARCHER").font(Theme.display(15)).tracking(1.5).lineLimit(1).fixedSize()
                }
                .foregroundStyle(Color.paper)
                .padding(.horizontal, 18)
                .frame(height: 44)
                .background(Capsule().fill(Color.ink))
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("LVL \(info.level)").font(Theme.display(18))
                Text("\(info.needed - info.into) xp to go").font(Theme.mono(11))
            }
            InkProgressBar(fraction: Double(info.into) / Double(info.needed), height: 10)
                .frame(width: 170)
        }
        .frame(width: 190)
    }

    private func edit() {
        services.haptics.selection()
        services.audio.play(.click)
        editingFace = true
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text).font(Theme.mono(12, bold: true)).tracking(2)
    }

    // MARK: Records

    private var records: some View {
        let s = progress.stats
        return HStack(spacing: 8) {
            statCard("\(s.wins)", "wins")
            statCard("\(s.bestStreak)", "best streak")
            statCard("\(s.headshots)", "headshots")
            statCard(s.longestHit > 0 ? "\(Int(s.longestHit))m" : "–", "longest hit")
            statCard("\(s.chickensKilled)", "chickens", chicken: true)
        }
    }

    private func statCard(_ value: String, _ label: String, chicken: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(value).font(Theme.display(24)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Theme.mono(10)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 62)
        .padding(.horizontal, 4)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.paper))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.ink, lineWidth: 2))
        .overlay(alignment: .top) {
            // The chicken lives on top of its box.
            if chicken { PerchingChicken().frame(height: 40).offset(y: -39) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(label): \(value)"))
    }

    // MARK: Hats

    private var hatRack: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Hat.allCases) { hat in hatTile(hat) }
            }
            .padding(.vertical, 2)
            .padding(.trailing, 12)
        }
    }

    private func hatTile(_ hat: Hat) -> some View {
        let unlocked = progress.isUnlocked(hat)
        let selected = progress.equippedHat == hat
        return Button {
            guard unlocked else { return }
            services.haptics.selection()
            services.audio.play(.click)
            progress.equippedHat = hat
            services.analytics.log("hat_equipped", ["hatId": hat.rawValue, "source": "profile"])
        } label: {
            VStack(spacing: 2) {
                ZStack {
                    PortraitView(look: .bjorn, hat: hat)
                        .frame(width: 58, height: 58)
                        .opacity(unlocked ? 1 : 0.25)
                    if !unlocked {
                        InkArtImage(key: "padlock", bounds: PropsArt.padlockBounds) { PropsArt.drawPadlock(&$0) }
                            .frame(width: 24)
                    }
                }
                Text(unlocked ? hat.title.lowercased() : hat.unlockText)
                    .font(Theme.mono(9, bold: selected))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .frame(height: 24)
                    .foregroundStyle(selected ? Color.paper : Color.ink)
            }
            .frame(width: 84, height: 96)
            .background(RoundedRectangle(cornerRadius: 14).fill(selected ? Color.ink : Color.paper))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.ink, style: StrokeStyle(lineWidth: 2.5, dash: unlocked ? [] : [5, 4])))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(unlocked ? "\(hat.title)\(selected ? ", wearing" : "")" : "\(hat.title), locked, \(hat.unlockText)"))
    }
}

/// A little chicken standing on the top edge of its record card, pottering
/// back and forth and pecking at nothing.
private struct PerchingChicken: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.services) private var services
    @State private var hop: CGFloat = 0
    @State private var x: CGFloat = 0.3
    @State private var facing: CGFloat = 1
    @State private var pose: ChickenArt.Pose = .stand

    var body: some View {
        GeometryReader { geo in
            let size: CGFloat = 40
            InkArtImage(key: "perch.\(pose.rawValue)", bounds: ChickenArt.bounds, dotSpacing: 1.6) {
                ChickenArt.draw(&$0, pose)
            }
            .frame(width: size * ChickenArt.bounds.width / ChickenArt.bounds.height, height: size)
            .scaleEffect(x: facing, y: 1)
            .offset(y: -hop)
            .position(x: 18 + x * max(0, geo.size.width - 36), y: geo.size.height / 2)
            .contentShape(Rectangle())
            .onTapGesture { poke() }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                if pose == .panic { try? await Task.sleep(for: .milliseconds(700)); continue }
                switch Int.random(in: 0..<4) {
                case 0, 1: // potter somewhere along the edge
                    let to = CGFloat.random(in: 0...1)
                    facing = to >= x ? 1 : -1
                    let seconds = Double(abs(to - x)) * 2.4 + 0.4
                    withAnimation(.linear(duration: seconds)) { x = to }
                    var t = 0.0
                    while t < seconds {
                        pose = pose == .step ? .stand : .step
                        try? await Task.sleep(for: .milliseconds(180))
                        t += 0.18
                    }
                    pose = .stand
                case 2: // peck, peck
                    for _ in 0..<2 {
                        pose = .peck
                        try? await Task.sleep(for: .milliseconds(260))
                        pose = .stand
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                default:
                    break
                }
                try? await Task.sleep(for: .milliseconds(Int.random(in: 900...2200)))
            }
        }
    }

    /// Poked: a startled flap and a hop.
    private func poke() {
        services.haptics.flutter()
        pose = .panic
        withAnimation(.easeOut(duration: 0.15)) { hop = 10 }
        withAnimation(.easeIn(duration: 0.18).delay(0.15)) { hop = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { pose = .stand }
    }
}

/// Bottom line of the profile: who you are online, and the way out.
private struct AccountRow: View {
    @ObservedObject var account: AccountStore
    let problem: String?
    let onChange: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("GAMERTAG").font(Theme.mono(12, bold: true)).tracking(2)
            Text(account.gamertag ?? "not picked yet").font(Theme.mono(14)).lineLimit(1)
            if let c = account.country { Text(c).font(Theme.mono(12, bold: true)).opacity(0.7) }
            Button(account.hasGamertag ? "change" : "pick one", action: onChange)
                .font(Theme.mono(13)).underline().buttonStyle(.plain)
            Spacer()
            if let problem { Text(problem).font(Theme.mono(12)).lineLimit(2) }
            Button("delete account", action: onDelete)
                .font(Theme.mono(12)).underline().opacity(0.7).buttonStyle(.plain)
        }
    }
}
