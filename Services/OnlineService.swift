import Foundation
import LongbowCore
import os
import Security

/// Talks to the Longbow Nakama server (spec A8, A22): device sign-in over
/// HTTP, server calls (RPCs), and the realtime socket that carries a duel.
/// Plain URLSession, no SDK: the protocol is small and JSON.
@MainActor
final class NakamaClient {
    struct ServerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    let host: String
    let port: Int
    /// HTTPS + secure WebSocket (the hosted server); plain only for a dev server.
    let secure: Bool
    private let serverKey: String
    private var token: String?
    private var tokenExpiry = Date.distantPast
    private(set) var userId: String?
    private let log = Logger(subsystem: "com.tejusrevi.longbow", category: "online")

    init(host: String, port: Int, secure: Bool, serverKey: String) {
        self.host = host
        self.port = port
        self.secure = secure
        self.serverKey = serverKey
    }

    /// The hosted server from Info.plist (`LongbowServerHost`, HTTPS on 443).
    /// Debug builds can use a dev server on the Mac instead:
    /// `-serverHost 10.0.0.101` (plain HTTP on 7350, key `longbow-local-key`).
    static func live() -> NakamaClient {
        let host = Bundle.main.object(forInfoDictionaryKey: "LongbowServerHost") as? String ?? "127.0.0.1"
        let key = Bundle.main.object(forInfoDictionaryKey: "LongbowServerKey") as? String ?? "longbow-local-key"
        #if DEBUG
        if let dev = UserDefaults.standard.string(forKey: "serverHost") {
            return NakamaClient(host: dev, port: 7350, secure: false,
                                serverKey: UserDefaults.standard.string(forKey: "serverKey") ?? "longbow-local-key")
        }
        #endif
        return NakamaClient(host: host, port: 443, secure: true, serverKey: key)
    }

    private var base: URL {
        var c = URLComponents()
        c.scheme = secure ? "https" : "http"; c.host = host
        if port != (secure ? 443 : 80) { c.port = port }
        return c.url!
    }

    // MARK: Sign-in

    /// Signs in with this device's account (created on first use).
    func session() async throws -> String {
        if let token, tokenExpiry > Date().addingTimeInterval(60) { return token }
        var req = URLRequest(url: base.appendingPathComponent("v2/account/authenticate/device")
            .appending(queryItems: [URLQueryItem(name: "create", value: "true")]))
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("Basic " + Data("\(serverKey):".utf8).base64EncodedString(), forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["id": DeviceIdentity.id])
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = json["token"] as? String else {
            throw ServerError(message: "Couldn't sign in to the server.")
        }
        token = t
        let claims = Self.claims(t)
        userId = claims["uid"] as? String
        tokenExpiry = Date(timeIntervalSince1970: claims["exp"] as? Double ?? 0)
        return t
    }

    private static func claims(_ jwt: String) -> [String: Any] {
        let parts = jwt.split(separator: ".")
        guard parts.count > 1 else { return [:] }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    // MARK: RPC

    /// Calls a server function with a JSON body; returns its JSON reply.
    func rpc(_ id: String, _ body: [String: Any]) async throws -> [String: Any] {
        let t = try await session()
        var req = URLRequest(url: base.appendingPathComponent("v2/rpc/\(id)"))
        req.httpMethod = "POST"
        req.timeoutInterval = 8
        req.setValue("Bearer " + t, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Nakama wants the payload as a JSON string inside the JSON body.
        let inner = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
        req.httpBody = try JSONSerialization.data(withJSONObject: inner, options: .fragmentsAllowed)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let outer = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = (outer["payload"] as? String)?.data(using: .utf8),
              let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            log.error("rpc \(id, privacy: .public) failed")
            throw ServerError(message: "The server didn't answer. Try again.")
        }
        return json
    }

    // MARK: Socket

    func openSocket() async throws -> RealtimeSocket {
        let t = try await session()
        var comps = URLComponents()
        comps.scheme = secure ? "wss" : "ws"; comps.host = host; comps.path = "/ws"
        if port != (secure ? 443 : 80) { comps.port = port }
        comps.queryItems = [URLQueryItem(name: "lang", value: "en"), URLQueryItem(name: "status", value: "false"),
                            URLQueryItem(name: "token", value: t)]
        let socket = RealtimeSocket(url: comps.url!)
        socket.connect()
        return socket
    }
}

/// The realtime connection: request/response envelopes matched by `cid`, and
/// match data pushed by the server.
@MainActor
final class RealtimeSocket {
    private let task: URLSessionWebSocketTask
    private var cid = 0
    private var waiting: [String: CheckedContinuation<[String: Any], Error>] = [:]
    /// (opCode, JSON body) for every match message from the server.
    var onMatchData: ((Int, [String: Any]) -> Void)?
    var onClose: (() -> Void)?
    private var closed = false

    init(url: URL) {
        task = URLSession.shared.webSocketTask(with: url)
    }

    func connect() {
        task.resume()
        receive()
    }

    private func receive() {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case let .success(message):
                    var data: Data?
                    switch message {
                    case let .string(s): data = s.data(using: .utf8)
                    case let .data(d): data = d
                    @unknown default: break
                    }
                    if let data, let env = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.handle(env) }
                    self.receive()
                case .failure:
                    self.shutDown()
                }
            }
        }
    }

    private func handle(_ env: [String: Any]) {
        if let cid = env["cid"] as? String, let cont = waiting.removeValue(forKey: cid) {
            if let err = env["error"] as? [String: Any] {
                cont.resume(throwing: NakamaClient.ServerError(message: err["message"] as? String ?? "error"))
            } else {
                cont.resume(returning: env)
            }
            return
        }
        guard let md = env["match_data"] as? [String: Any],
              let opString = md["op_code"] as? String, let op = Int(opString) else { return }
        var body: [String: Any] = [:]
        if let b64 = md["data"] as? String, let raw = Data(base64Encoded: b64),
           let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] { body = obj }
        onMatchData?(op, body)
    }

    /// Sends a request and waits for its reply.
    func request(_ envelope: [String: Any]) async throws -> [String: Any] {
        cid += 1
        let id = String(cid)
        var env = envelope
        env["cid"] = id
        let data = try JSONSerialization.data(withJSONObject: env)
        return try await withCheckedThrowingContinuation { cont in
            waiting[id] = cont
            task.send(.string(String(data: data, encoding: .utf8)!)) { [weak self] error in
                guard let error else { return }
                Task { @MainActor in self?.waiting.removeValue(forKey: id)?.resume(throwing: error) }
            }
        }
    }

    /// Fire-and-forget match message.
    func send(matchId: String, op: Int, body: [String: Any]) {
        guard let raw = try? JSONSerialization.data(withJSONObject: body),
              let data = try? JSONSerialization.data(withJSONObject: [
                  "match_data_send": ["match_id": matchId, "op_code": String(op), "data": raw.base64EncodedString()],
              ]) else { return }
        task.send(.string(String(data: data, encoding: .utf8)!)) { _ in }
    }

    func close() {
        task.cancel(with: .normalClosure, reason: nil)
        shutDown()
    }

    private func shutDown() {
        guard !closed else { return }
        closed = true
        for (_, c) in waiting { c.resume(throwing: NakamaClient.ServerError(message: "Connection lost.")) }
        waiting.removeAll()
        onClose?()
    }
}

/// This device's account id, kept in the Keychain so it survives reinstalls.
enum DeviceIdentity {
    private static let service = "com.tejusrevi.longbow.device"

    static let id: String = {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true]
        var out: AnyObject?
        if SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let d = out as? Data,
           let s = String(data: d, encoding: .utf8) { return s }
        var new = UUID().uuidString
        #if DEBUG
        // Two simulators on one Mac share nothing, but a test can force a fresh identity.
        if let tag = UserDefaults.standard.string(forKey: "deviceTag") { new = "dev-\(tag)-\(new)" }
        #endif
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecValueData as String: Data(new.utf8),
                                  kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        SecItemAdd(add as CFDictionary, nil)
        return new
    }()
}

// MARK: - Friend duel

/// Wire protocol op codes (mirrors Server/src/duel.ts).
enum DuelOp {
    static let shot = 1, ready = 2, leave = 3
    static let start = 10, result = 11, end = 12, opponentAway = 13, opponentBack = 14, reject = 15
}

/// Everything the server says when a duel begins.
struct DuelStart: Equatable {
    struct Player: Equatable {
        let userId: String
        let name: String
        let avatar: Avatar
        let hat: Hat
    }

    let seedHex: String
    let roundsToWin: Int
    let challenge: HitChallenge
    let firstShooter: Int
    let players: [Player]
    /// Which seat is this device (0 = left).
    let seat: Int

    var seed: UInt64 { UInt64(seedHex.dropFirst(2), radix: 16) ?? 0 }
}

/// One official shot result from the server.
struct DuelResult: Equatable {
    let turn: Int
    let shooter: Int
    let input: ShotInput
    let health: [Int]
    let timedOut: Bool
}

/// A friend duel from lobby to final whistle. The lobby UI watches `stage`;
/// once the match is running, `MatchController` takes the result/end hooks.
@MainActor
final class FriendDuel: ObservableObject, Identifiable {
    enum Stage: Equatable {
        case idle, connecting, waiting(code: String), started(DuelStart), failed(String)
    }

    let id = UUID()
    @Published private(set) var stage: Stage = .idle
    private let client: NakamaClient
    private var socket: RealtimeSocket?
    private(set) var matchId: String?
    private var pendingStart: [String: Any]?

    // Hooks for the running match.
    var onResult: ((DuelResult) -> Void)?
    var onEnd: ((_ winner: Int, _ reason: String) -> Void)?
    var onPresence: ((_ seat: Int, _ away: Bool) -> Void)?
    private var bufferedResults: [DuelResult] = []

    init(client: NakamaClient) {
        self.client = client
    }

    struct Me {
        let name: String
        let avatar: Avatar
        let hat: Hat
    }

    func create(challenge: HitChallenge, me: Me) {
        run(me: me) { client in
            let r = try await client.rpc("create_duel", ["challenge": challenge.rawValue])
            guard let code = r["code"] as? String, let id = r["matchId"] as? String else {
                throw NakamaClient.ServerError(message: "Couldn't start a duel.")
            }
            return (id, code)
        }
    }

    func join(code: String, me: Me) {
        run(me: me) { client in
            let r = try await client.rpc("join_duel", ["code": code])
            if let err = r["error"] as? String {
                throw NakamaClient.ServerError(message: err == "full" ? "That duel already has two archers." :
                    "No duel with that code. Check the letters?")
            }
            guard let id = r["matchId"] as? String else { throw NakamaClient.ServerError(message: "Couldn't join.") }
            return (id, nil)
        }
    }

    private func run(me: Me, _ find: @escaping (NakamaClient) async throws -> (String, String?)) {
        stage = .connecting
        Task {
            do {
                let (id, code) = try await find(client)
                let socket = try await client.openSocket()
                self.socket = socket
                self.matchId = id
                socket.onMatchData = { [weak self] op, body in self?.handle(op, body) }
                socket.onClose = { [weak self] in
                    guard let self else { return }
                    if case .started = self.stage { self.onEnd?(-1, "disconnected") } else {
                        self.stage = .failed("Lost the connection to the server.")
                    }
                }
                let avatar = String(data: (try? JSONEncoder().encode(me.avatar)) ?? Data(), encoding: .utf8) ?? "{}"
                let reply = try await socket.request(["match_join": [
                    "match_id": id, "metadata": ["name": me.name, "avatar": avatar, "hat": me.hat.rawValue],
                ]])
                if reply["error"] != nil { throw NakamaClient.ServerError(message: "Couldn't join that duel.") }
                if case .started = stage { return }
                stage = .waiting(code: code ?? "")
            } catch {
                stage = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't reach the server.")
            }
        }
    }

    private func handle(_ op: Int, _ body: [String: Any]) {
        switch op {
        case DuelOp.start:
            guard let start = parseStart(body) else { return }
            if case .started = stage {
                // A reconnect: the server replays the history; results we haven't applied are delivered.
                return
            }
            stage = .started(start)
        case DuelOp.result:
            guard let r = parseResult(body) else { return }
            if let onResult { onResult(r) } else { bufferedResults.append(r) }
        case DuelOp.end:
            onEnd?(body["winner"] as? Int ?? -1, body["reason"] as? String ?? "won")
        case DuelOp.opponentAway:
            onPresence?(body["seat"] as? Int ?? -1, true)
        case DuelOp.opponentBack:
            onPresence?(body["seat"] as? Int ?? -1, false)
        default:
            break
        }
    }

    /// Hands over any results that arrived before the match screen was ready.
    func attach(onResult: @escaping (DuelResult) -> Void) {
        self.onResult = onResult
        let pending = bufferedResults
        bufferedResults.removeAll()
        pending.forEach(onResult)
    }

    private func parseStart(_ b: [String: Any]) -> DuelStart? {
        guard let seed = b["seed"] as? String, let seats = b["seats"] as? [Any] else { return nil }
        let me = client.userId
        var players: [DuelStart.Player] = []
        var mine = 0
        for (i, s) in seats.enumerated() {
            guard let s = s as? [String: Any] else { return nil }
            let uid = s["userId"] as? String ?? ""
            if uid == me { mine = i }
            var avatar = Avatar.bjorn
            if let a = s["avatar"], let data = try? JSONSerialization.data(withJSONObject: a),
               let decoded = try? JSONDecoder().decode(Avatar.self, from: data) { avatar = decoded }
            players.append(.init(userId: uid, name: (s["name"] as? String ?? "ARCHER").uppercased(), avatar: avatar,
                                 hat: Hat(rawValue: s["hat"] as? String ?? "") ?? .none))
        }
        return DuelStart(seedHex: seed, roundsToWin: b["roundsToWin"] as? Int ?? 3,
                         challenge: HitChallenge(rawValue: b["challenge"] as? String ?? "") ?? .medium,
                         firstShooter: b["firstShooter"] as? Int ?? 0, players: players, seat: mine)
    }

    private func parseResult(_ b: [String: Any]) -> DuelResult? {
        guard let turn = b["turn"] as? Int, let shooter = b["shooter"] as? Int,
              let a = b["angleTenths"] as? Int, let p = b["powerPermille"] as? Int else { return nil }
        return DuelResult(turn: turn, shooter: shooter, input: ShotInput(angleTenths: a, powerPermille: p),
                          health: b["health"] as? [Int] ?? [], timedOut: b["timedOut"] as? Bool ?? false)
    }

    // MARK: During the match

    func sendShot(turn: Int, input: ShotInput) {
        guard let matchId else { return }
        socket?.send(matchId: matchId, op: DuelOp.shot,
                     body: ["turn": turn, "angleTenths": input.angleTenths, "powerPermille": input.powerPermille])
    }

    /// The next shooter has finished watching: their shot clock starts on the server.
    func sendReady(turn: Int) {
        guard let matchId else { return }
        socket?.send(matchId: matchId, op: DuelOp.ready, body: ["turn": turn])
    }

    func leave() {
        if let matchId { socket?.send(matchId: matchId, op: DuelOp.leave, body: [:]) }
        Task { [socket] in
            try? await Task.sleep(for: .milliseconds(300))
            socket?.close()
        }
        onResult = nil
        onEnd = nil
    }

    func close() {
        socket?.close()
        socket = nil
    }
}
