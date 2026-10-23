import Foundation

/// Your online identity (spec A7.1): gamertag and country, kept on the server
/// and cached here so screens can show them offline. Also deletes the account.
@MainActor
final class AccountStore: ObservableObject {
    enum ProfileError: LocalizedError {
        case invalid, notAllowed, taken, badCountry, offline

        var errorDescription: String? {
            switch self {
            case .invalid: return "3 to 16 letters, numbers or _"
            case .notAllowed: return "Pick a different gamertag."
            case .taken: return "Someone already has that one."
            case .badCountry: return "Pick your country."
            case .offline: return "Couldn't reach the server. Try again?"
            }
        }
    }

    @Published private(set) var gamertag: String?
    @Published private(set) var country: String?
    private let client: NakamaClient
    private let defaults: UserDefaults

    init(client: NakamaClient, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        gamertag = defaults.string(forKey: "gamertag")
        country = defaults.string(forKey: "country")
    }

    var hasGamertag: Bool { gamertag != nil }

    /// Your country as a two-letter code, or this phone's region until you pick.
    var countryOrGuess: String { country ?? Countries.deviceRegion }

    /// Reads the profile back from the server (another device may have set it).
    func refresh() async {
        guard let r = try? await client.rpc("get_profile", [:]) else { return }
        apply(gamertag: r["gamertag"] as? String, country: r["country"] as? String)
    }

    func save(gamertag: String, country: String) async throws {
        let r: [String: Any]
        do {
            r = try await client.rpc("set_profile", ["gamertag": gamertag, "country": country])
        } catch {
            throw ProfileError.offline
        }
        switch r["error"] as? String {
        case "invalid": throw ProfileError.invalid
        case "not_allowed": throw ProfileError.notAllowed
        case "taken": throw ProfileError.taken
        case "bad_country": throw ProfileError.badCountry
        default: break
        }
        apply(gamertag: r["gamertag"] as? String, country: r["country"] as? String)
    }

    /// Deletes the account on the server, then forgets this device's identity
    /// and everything stored locally, so the next launch starts from scratch.
    func deleteAccount(progress: ProgressStore) async throws {
        do {
            _ = try await client.rpc("delete_account", [:])
        } catch {
            throw ProfileError.offline
        }
        client.signOut()
        DeviceIdentity.reset()
        apply(gamertag: nil, country: nil)
        progress.resetAll()
        for key in ["onlineName", "onlineChallenge"] { defaults.removeObject(forKey: key) }
    }

    private func apply(gamertag: String?, country: String?) {
        self.gamertag = gamertag
        self.country = country
        defaults.set(gamertag, forKey: "gamertag")
        defaults.set(country, forKey: "country")
    }
}

/// Countries for the picker: ISO 3166 two-letter codes with their names in
/// the player's language, sorted by name.
enum Countries {
    struct Entry: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
    }

    static let all: [Entry] = {
        let locale = Locale.current
        return Locale.Region.isoRegions
            .filter { $0.identifier.count == 2 && $0.identifier.allSatisfy(\.isLetter) }
            .compactMap { r in locale.localizedString(forRegionCode: r.identifier).map { Entry(code: r.identifier, name: $0) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static var deviceRegion: String {
        let code = Locale.current.region?.identifier ?? "CA"
        return code.count == 2 ? code : "CA"
    }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }

    /// Gamertag rules, mirrored from the server so typing feels instant.
    static let gamertagCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
}
