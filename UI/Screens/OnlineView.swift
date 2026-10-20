import LongbowCore
import SwiftUI

/// Friend duel lobby (spec A7.2, `Online.dc.html`): start a duel and share its
/// 4-character code, or type a friend's code to join. The match starts the
/// moment both archers are in.
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
                })
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
    @AppStorage("onlineName") private var name = "ARCHER"
    @AppStorage("onlineChallenge") private var challengeRaw = HitChallenge.medium.rawValue
    @State private var code = ""
    @FocusState private var codeFocused: Bool

    private var me: FriendDuel.Me {
        FriendDuel.Me(name: name.trimmingCharacters(in: .whitespaces).isEmpty ? "ARCHER" : name,
                      avatar: progress.avatar, hat: progress.equippedHat)
    }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
                .onTapGesture { codeFocused = false }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    BackButton(action: onClose)
                    Text("FRIEND DUEL").font(Theme.display(30)).accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                switch duel.stage {
                case .idle, .failed:
                    lobby
                case .connecting:
                    status("calling the server...")
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
        #if DEBUG
        // Test hooks: `-onlineCreate YES -codeFile /path` or `-onlineJoin ABCD`.
        .task {
            let d = UserDefaults.standard
            if d.bool(forKey: "onlineCreate") { duel.create(challenge: HitChallenge(rawValue: challengeRaw) ?? .medium, me: me) }
            if let code = d.string(forKey: "onlineJoin") { duel.join(code: code, me: me) }
        }
        #endif
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
                label("YOUR NAME")
                TextField("ARCHER", text: Binding(get: { name }, set: { name = String($0.uppercased().prefix(12)) }))
                    .font(Theme.display(20))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.ink, lineWidth: 2))
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
                Text("the one who starts the duel picks").font(Theme.hand(15)).opacity(0.7)
                if case let .failed(message) = duel.stage {
                    Text(message).font(Theme.hand(17)).padding(.top, 6)
                }
            }
            .frame(width: 280, alignment: .leading)

            VStack(alignment: .leading, spacing: 14) {
                Button("START A DUEL") {
                    services.haptics.selection()
                    duel.create(challenge: HitChallenge(rawValue: challengeRaw) ?? .medium, me: me)
                }
                .buttonStyle(PillButtonStyle(primary: true))

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
                Text("waiting for your friend...").font(Theme.hand(24))
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

    private func status(_ text: String) -> some View {
        Text(text).font(Theme.hand(26)).padding(.top, 30).frame(maxWidth: .infinity)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.mono(12, bold: true)).tracking(2)
    }
}
