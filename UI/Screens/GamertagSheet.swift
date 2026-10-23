import SwiftUI

/// Pick (or change) your gamertag and country (A7.1). Shown before your first
/// online duel, and from the profile. Left: the gamertag and SAVE. Right: a
/// searchable country list, starting on this phone's region.
struct GamertagSheet: View {
    /// Called after a successful save (or a close when there was nothing to do).
    let onDone: () -> Void
    var onCancel: (() -> Void)?
    @ObservedObject var account: AccountStore
    @Environment(\.services) private var services
    @State private var tag = ""
    @State private var country = ""
    @State private var search = ""
    @State private var problem: String?
    @State private var saving = false
    @FocusState private var tagFocused: Bool

    private var tagIsValid: Bool { (3...16).contains(tag.count) }

    var body: some View {
        ZStack {
            Color.paper.ignoresSafeArea()
                .onTapGesture { tagFocused = false }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    if let onCancel { BackButton(action: onCancel) }
                    Text(account.hasGamertag ? "YOUR GAMERTAG" : "PICK A GAMERTAG")
                        .font(Theme.display(30)).accessibilityAddTraits(.isHeader)
                    Spacer()
                }
                HStack(alignment: .top, spacing: 26) {
                    left.frame(width: 300, alignment: .leading)
                    countries
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
        }
        .onAppear {
            tag = account.gamertag ?? ""
            country = account.countryOrGuess
        }
    }

    // MARK: Gamertag

    private var left: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("GAMERTAG")
            TextField("ArrowSmith", text: Binding(get: { tag }, set: {
                tag = String($0.filter { Countries.gamertagCharacters.contains($0) }.prefix(16))
                problem = nil
            }))
            .font(Theme.display(24))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.asciiCapable)
            .focused($tagFocused)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.ink, lineWidth: 2.5))
            Text(problem ?? "3 to 16 letters, numbers or _. Everyone you duel sees it.")
                .font(Theme.mono(13))
                .opacity(problem == nil ? 0.7 : 1)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                label("COUNTRY")
                Text(Countries.name(country)).font(Theme.mono(14)).lineLimit(1)
            }
            .padding(.top, 4)
            Button(saving ? "SAVING..." : "SAVE", action: save)
                .buttonStyle(PillButtonStyle(primary: true))
                .opacity(tagIsValid && !saving ? 1 : 0.4)
                .disabled(!tagIsValid || saving)
                .padding(.top, 6)
        }
    }

    // MARK: Country

    private var countries: some View {
        let q = search.trimmingCharacters(in: .whitespaces)
        let shown = q.isEmpty ? Countries.all : Countries.all.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.code.caseInsensitiveCompare(q) == .orderedSame
        }
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Search countries", text: $search)
                .font(Theme.mono(15))
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.ink, lineWidth: 2))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(shown) { c in
                            let on = c.code == country
                            Button {
                                country = c.code
                                services.haptics.selection()
                            } label: {
                                HStack {
                                    Text(c.name).font(Theme.mono(15, bold: on)).lineLimit(1)
                                    Spacer()
                                    Text(c.code).font(Theme.mono(13, bold: true)).opacity(0.7)
                                }
                                .foregroundStyle(on ? Color.paper : Color.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 38)
                                .background(RoundedRectangle(cornerRadius: 10).fill(on ? Color.ink : Color.clear))
                            }
                            .buttonStyle(.plain)
                            .id(c.code)
                            .accessibilityAddTraits(on ? .isSelected : [])
                        }
                    }
                }
                // Start on your country (after onAppear has filled it in).
                .task { proxy.scrollTo(country.isEmpty ? account.countryOrGuess : country, anchor: .center) }
            }
        }
    }

    private func save() {
        tagFocused = false
        saving = true
        Task {
            do {
                try await account.save(gamertag: tag, country: country)
                services.haptics.success()
                onDone()
            } catch {
                problem = (error as? LocalizedError)?.errorDescription ?? "Couldn't save. Try again?"
                services.haptics.nearMiss()
            }
            saving = false
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(Theme.mono(12, bold: true)).tracking(2)
    }
}
