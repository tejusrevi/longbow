import LongbowCore
import SwiftUI

/// Online lobby (spec A7.2, A7.3, `Online.dc.html`): quick match against
/// anyone who's looking, or a friend duel by 4-character code. The match
/// starts the moment both archers are in. Needs a gamertag first.
struct OnlineView: View {
    let onStart: (OnlineMatch) -> Void
    let onClose: () -> Void
    @Environment(\.services) private var services
    @State private var duel: FriendDuel?

    var body: some View {
        Group {
            if let duel {
                DuelLobby(duel: duel, onStart: onStart, onClose: {
                    duel.close()
                    onClose()
                }, account: services.account)
            } else {
                Color.paper
            }
        }
        .onAppear {
            if duel == nil { duel = FriendDuel(client: services.online) }
        }
    }
}

private struct DuelLobby: View {
    @ObservedObject var duel: FriendDuel
    let onStart: (OnlineMatch) -> Void
    let onClose: () -> Void
    @Environment(\.services) private var services
    @EnvironmentObject private var progress: ProgressStore
    @ObservedObject private var account: AccountStore
    @AppStorage("onlineChallenge") private var challengeRaw = HitChallenge.medium.rawValue
    @State private var code = ""
    @State private var editingTag = false
    @FocusState private var codeFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var push = PushService.shared

    init(duel: FriendDuel, onStart: @escaping (OnlineMatch) -> Void, onClose: @escaping () -> Void, account: AccountStore) {
        self.duel = duel
        self.onStart = onStart
        self.onClose = onClose
        self.account = account
    }

    private var me: FriendDuel.Me {
        FriendDuel.Me(name: account.gamertag ?? "ARCHER", avatar: progress.avatar, hat: progress.equippedHat)
    }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
                .onTapGesture { codeFocused = false }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    BackButton(action: onClose)
                    Text("ONLINE").font(Theme.display(30)).accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                switch duel.stage {
                case .idle, .failed:
                    lobby
                case .connecting:
                    status("calling the server...")
                case .searching:
                    searching
                case let .waiting(code) where !code.isEmpty:
                    waiting(code)
                case .waiting:
                    status("joining your friend's duel...")
                case .started:
                    status("here we go!")
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .fullScreenCover(isPresented: $editingTag) {
            GamertagSheet(onDone: { editingTag = false }, onCancel: {
                editingTag = false
                // No gamertag, no online play: back to the title.
                if !account.hasGamertag { onClose() }
            }, account: account)
            .environment(\.services, services)
        }
        .task {
            // Game Center first, so a returning player lands on their own account.
            GameCenterAuth.shared.start()
            await account.refresh()
            #if DEBUG
            // Test hooks: `-onlineName ALICE` picks a gamertag on a fresh device;
            // `-onlineCreate YES -codeFile /path`, `-onlineJoin ABCD` or `-onlineQuick YES`.
            let d = UserDefaults.standard
            if !account.hasGamertag, let name = d.string(forKey: "onlineName") {
                try? await account.save(gamertag: "\(name)_\(Int.random(in: 100...999))", country: "CA")
            }
            if account.hasGamertag {
                if d.bool(forKey: "onlineCreate") { duel.create(challenge: HitChallenge(rawValue: challengeRaw) ?? .medium, me: me) }
                if let code = d.string(forKey: "onlineJoin") { duel.join(code: code, me: me) }
                if d.bool(forKey: "onlineQuick") { duel.quickMatch(me: me) }
            }
            #endif
            if !account.hasGamertag { editingTag = true }
            openPendingDuel()
        }
        .onChange(of: push.pendingMatchId) { _, _ in openPendingDuel() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { duel.resume(me: me) }
        }
        .onChange(of: duel.stage) { _, stage in
            #if DEBUG
            if case let .waiting(code) = stage, !code.isEmpty, let path = UserDefaults.standard.string(forKey: "codeFile") {
                try? code.write(toFile: path, atomically: true, encoding: .utf8)
            }
            #endif
            if case let .started(start) = stage {
                services.haptics.success()
                onStart(OnlineMatch(duel: duel, start: start))
            }
        }
    }

    // MARK: Lobby

    private var lobby: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                label("PLAYING AS")
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(account.gamertag ?? "...").font(Theme.display(22)).lineLimit(1).minimumScaleFactor(0.6)
                    if let c = account.country { Text(c).font(Theme.mono(13, bold: true)).opacity(0.7) }
                    Button("change") { editingTag = true }
                        .font(Theme.mono(14))
                        .underline()
                        .buttonStyle(.plain)
                }
                label("HOW HARD").padding(.top, 6)
                HStack(spacing: 8) {
                    ForEach(HitChallenge.allCases, id: \.self) { c in
                        let on = challengeRaw == c.rawValue
                        Button {
                            challengeRaw = c.rawValue
                            services.haptics.selection()
                        } label: {
                            Text(c.rawValue.uppercased())
                                .font(Theme.mono(13, bold: on))
                                .foregroundStyle(on ? Color.paper : Color.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 36)
                                .background(Capsule().fill(on ? Color.ink : Color.paper))
                                .overlay(Capsule().strokeBorder(Color.ink, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                Text("for friend duels. quick match is medium.").font(Theme.mono(12)).opacity(0.7)
                if case let .failed(message) = duel.stage {
                    Text(message).font(Theme.mono(14)).padding(.top, 6)
                }
            }
            .frame(width: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                Button("QUICK MATCH") {
                    services.haptics.selection()
                    duel.quickMatch(me: me)
                }
                .buttonStyle(PillButtonStyle(primary: true))
                Button("DUEL A FRIEND") {
                    services.haptics.selection()
                    // So we can tell you when they join while you're off sending the code.
                    PushService.shared.requestIfNeeded()
                    duel.create(challenge: HitChallenge(rawValue: challengeRaw) ?? .medium, me: me)
                }
                .buttonStyle(PillButtonStyle(primary: false))

                label("OR JOIN WITH A CODE").padding(.top, 4)
                HStack(spacing: 12) {
                    TextField("ABCD", text: Binding(get: { code }, set: { code = Self.clean($0) }))
                        .font(Theme.display(30))
                        .tracking(8)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .focused($codeFocused)
                        .multilineTextAlignment(.center)
                        .frame(width: 170, height: 62)
                        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.ink, lineWidth: 2.5))
                        .submitLabel(.join)
                        .onSubmit(joinIfReady)
                    Button("JOIN", action: joinIfReady)
                        .buttonStyle(PillButtonStyle(primary: false))
                        .frame(width: 140)
                        .opacity(code.count == 4 ? 1 : 0.4)
                        .disabled(code.count != 4)
                }
            }
            .frame(maxWidth: 360)
        }
    }

    /// A tapped "your friend joined" notification: back into that duel.
    private func openPendingDuel() {
        guard account.hasGamertag, let id = push.pendingMatchId else { return }
        push.pendingMatchId = nil
        if duel.matchId == id { duel.resume(me: me); return }
        duel.rejoin(matchId: id, code: push.pendingCode, me: me)
    }

    private func joinIfReady() {
        guard code.count == 4 else { return }
        codeFocused = false
        services.haptics.selection()
        duel.join(code: code, me: me)
    }

    /// Letters and digits only. Codes never use the look-alikes O/0 and I/1.
    private static func clean(_ s: String) -> String {
        let allowed = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        return String(s.uppercased().filter { allowed.contains($0) }.prefix(4))
    }

    // MARK: Waiting

    private func waiting(_ code: String) -> some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(alignment: .leading, spacing: 10) {
                label("YOUR DUEL CODE")
                HStack(spacing: 8) {
                    ForEach(Array(code), id: \.self) { ch in
                        Text(String(ch))
                            .font(Theme.display(44))
                            .frame(width: 58, height: 70)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.paper))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ink, lineWidth: 3))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Duel code \(code.map(String.init).joined(separator: " "))"))
                ShareLink(item: "Duel me in Longbow! Open the game, tap Multi Player → Online, and enter \(code).") {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .bold))
                        Text("SEND TO A FRIEND").font(Theme.display(15)).tracking(1.5)
                    }
                    .foregroundStyle(Color.paper)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(Capsule().fill(Color.ink))
                }
                .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("waiting for your friend...").font(Theme.mono(19))
                Text("the duel starts as soon as they join.").font(Theme.mono(13)).opacity(0.75)
                Button("CANCEL") {
                    duel.close()
                    onClose()
                }
                .buttonStyle(PillButtonStyle(primary: false))
                .frame(width: 180)
                .padding(.top, 10)
            }
        }
        .padding(.top, 8)
    }

    // MARK: Quick match

    private var searching: some View {
        VStack(spacing: 10) {
            Text("looking for an archer...").font(Theme.mono(21))
            Text("anyone in the world who taps quick match right now.").font(Theme.mono(13)).opacity(0.75)
            Button("CANCEL") {
                services.haptics.selection()
                duel.cancelSearch()
            }
            .buttonStyle(PillButtonStyle(primary: false))
            .frame(width: 180)
            .padding(.top, 10)
        }
        .padding(.top, 30)
        .frame(maxWidth: .infinity)
    }

    private func status(_ text: String) -> some View {
        Text(text).font(Theme.mono(21)).padding(.top, 30).frame(maxWidth: .infinity)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.mono(12, bold: true)).tracking(2)
    }
}
