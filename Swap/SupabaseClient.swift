import Foundation
import Security

// MARK: - Config

enum Backend {
    /// Returns nil (demo mode) unless SUPABASE_URL and SUPABASE_ANON_KEY were set in Config/Secrets.xcconfig.
    static func makeClient() -> SupabaseClient? {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "demoMode") { return nil }
        #endif
        let info = Bundle.main.infoDictionary
        guard let urlString = info?["SupabaseURL"] as? String,
              let key = info?["SupabaseAnonKey"] as? String,
              !urlString.isEmpty, !key.isEmpty,
              !urlString.contains("$("), !key.contains("$("),
              let url = URL(string: urlString), url.scheme == "https" else { return nil }
        return SupabaseClient(config: .init(url: url, anonKey: key))
    }
}

enum BackendError: LocalizedError {
    case http(Int, String)
    case signedOut
    case confirmEmail

    var errorDescription: String? {
        switch self {
        case .http(_, let message): return message
        case .signedOut: return "Your session expired. Please sign in again."
        case .confirmEmail: return "Check your email to confirm your account, then sign in."
        }
    }
}

// MARK: - Session and Keychain

struct Session: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
    var email: String
    var name: String
}

enum Keychain {
    private static let service = "swap.session"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: "current"]
    }

    static func load() -> Session? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func save(_ session: Session?) {
        SecItemDelete(base as CFDictionary)
        guard let session, let data = try? JSONEncoder().encode(session) else { return }
        var q = base
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

// MARK: - JSON

enum JSON {
    private static func parseDate(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(s) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                        debugDescription: "Bad date \(s)"))
            }
            return date
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()
}

// MARK: - Wire types

private struct AuthUser: Decodable {
    struct Meta: Decodable {
        var name: String?
        var fullName: String?
    }
    var id: UUID
    var email: String?
    var userMetadata: Meta?
}

private struct AuthResponse: Decodable {
    var accessToken: String?
    var refreshToken: String?
    var expiresIn: Double?
    var user: AuthUser?
}

struct ProfileName: Decodable { var name: String? }

struct ListingRow: Decodable {
    var id: UUID
    var sellerId: UUID
    var title: String
    var price: Double
    var category: String
    var condition: String
    var details: String
    var locationName: String
    var photoUrls: [String]
    var isSold: Bool
    var createdAt: Date
    var profiles: ProfileName?

    func toListing() -> Listing {
        Listing(id: id, title: title, price: price,
                category: Category(rawValue: category) ?? .other,
                condition: Condition(rawValue: condition) ?? .good,
                details: details, locationName: locationName, distanceMiles: 0,
                sellerID: sellerId, sellerName: profiles?.name?.isEmpty == false ? profiles!.name! : "Seller",
                photoURLs: photoUrls, createdAt: createdAt, isSold: isSold)
    }
}

private struct NewListing: Encodable {
    var id: UUID
    var title: String
    var price: Double
    var category: String
    var condition: String
    var details: String
    var locationName: String
    var photoUrls: [String]
}

private struct MessageRow: Decodable {
    var id: UUID
    var senderId: UUID
    var body: String
    var createdAt: Date
}

private struct ThreadRow: Decodable {
    struct ListingTitle: Decodable { var title: String? }
    var id: UUID
    var listingId: UUID
    var buyerId: UUID
    var sellerId: UUID
    var listings: ListingTitle?
    var buyer: ProfileName?
    var seller: ProfileName?
    var messages: [MessageRow]
}

private struct FavoriteRow: Decodable { var listingId: UUID }
private struct BlockRow: Decodable { var blockedId: UUID }

// MARK: - Client

actor SupabaseClient {
    struct Config {
        let url: URL
        let anonKey: String
    }

    private let config: Config
    private let http = URLSession.shared
    private(set) var session: Session?

    init(config: Config) {
        self.config = config
        self.session = Keychain.load()
    }

    // MARK: Auth

    func signUp(name: String, email: String, password: String) async throws -> Session {
        let payload: [String: Any] = ["email": email, "password": password, "data": ["name": name]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send("POST", "auth/v1/signup", body: body, authed: false)
        let resp = try JSON.decoder.decode(AuthResponse.self, from: data)
        guard let s = makeSession(resp, fallbackName: name) else { throw BackendError.confirmEmail }
        setSession(s)
        return s
    }

    func signIn(email: String, password: String) async throws -> Session {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send("POST", "auth/v1/token", query: [.init(name: "grant_type", value: "password")],
                                  body: body, authed: false)
        let resp = try JSON.decoder.decode(AuthResponse.self, from: data)
        guard let s = makeSession(resp, fallbackName: "") else { throw BackendError.signedOut }
        setSession(s)
        return s
    }

    /// Address of the provider sign in page (Google). Uses the PKCE code flow.
    func oauthURL(provider: String, redirectTo: String, challenge: String) -> URL {
        var comps = URLComponents(url: config.url.appending(path: "auth/v1/authorize"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "provider", value: provider),
            .init(name: "redirect_to", value: redirectTo),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "s256"),
        ]
        return comps.url!
    }

    func exchangeCode(_ code: String, verifier: String) async throws -> Session {
        let body = try JSONSerialization.data(withJSONObject: ["auth_code": code, "code_verifier": verifier])
        let data = try await send("POST", "auth/v1/token", query: [.init(name: "grant_type", value: "pkce")],
                                  body: body, authed: false)
        let resp = try JSON.decoder.decode(AuthResponse.self, from: data)
        guard let s = makeSession(resp, fallbackName: "") else { throw BackendError.signedOut }
        setSession(s)
        return s
    }

    func signOut() async {
        _ = try? await send("POST", "auth/v1/logout", retry: false)
        setSession(nil)
    }

    private func refresh() async throws {
        guard let current = session else { throw BackendError.signedOut }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": current.refreshToken])
        do {
            let data = try await send("POST", "auth/v1/token", query: [.init(name: "grant_type", value: "refresh_token")],
                                      body: body, authed: false)
            let resp = try JSON.decoder.decode(AuthResponse.self, from: data)
            guard var s = makeSession(resp, fallbackName: current.name) else { throw BackendError.signedOut }
            if s.name.isEmpty { s.name = current.name }
            setSession(s)
        } catch {
            setSession(nil)
            throw BackendError.signedOut
        }
    }

    private func makeSession(_ r: AuthResponse, fallbackName: String) -> Session? {
        guard let access = r.accessToken, let refresh = r.refreshToken, let user = r.user else { return nil }
        var name = user.userMetadata?.name ?? user.userMetadata?.fullName ?? fallbackName
        if name.isEmpty { name = user.email?.split(separator: "@").first.map(String.init) ?? "" }
        return Session(accessToken: access, refreshToken: refresh,
                       expiresAt: Date().addingTimeInterval(r.expiresIn ?? 3600),
                       userID: user.id, email: user.email ?? "", name: name)
    }

    private func setSession(_ s: Session?) {
        session = s
        Keychain.save(s)
    }

    // MARK: Listings

    func fetchListings() async throws -> [ListingRow] {
        let data = try await send("GET", "rest/v1/listings", query: [
            .init(name: "select", value: "*,profiles!seller_id(name)"),
            .init(name: "order", value: "created_at.desc"),
            .init(name: "limit", value: "200"),
        ])
        return try JSON.decoder.decode([ListingRow].self, from: data)
    }

    func createListing(id: UUID, title: String, price: Double, category: Category, condition: Condition,
                       details: String, location: String, photoURLs: [String]) async throws {
        let payload = NewListing(id: id, title: title, price: price, category: category.rawValue,
                                 condition: condition.rawValue, details: details, locationName: location,
                                 photoUrls: photoURLs)
        _ = try await send("POST", "rest/v1/listings", body: try JSON.encoder.encode(payload),
                           extra: ["Prefer": "return=minimal"])
    }

    func markSold(_ id: UUID) async throws {
        _ = try await send("PATCH", "rest/v1/listings", query: [.init(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                           body: try JSONSerialization.data(withJSONObject: ["is_sold": true]),
                           extra: ["Prefer": "return=minimal"])
    }

    func deleteListing(_ id: UUID) async throws {
        _ = try await send("DELETE", "rest/v1/listings", query: [.init(name: "id", value: "eq.\(id.uuidString.lowercased())")])
    }

    // MARK: Photos

    func uploadPhoto(_ jpeg: Data) async throws -> String {
        guard let uid = session?.userID else { throw BackendError.signedOut }
        let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        _ = try await send("POST", "storage/v1/object/listing-photos/\(path)", body: jpeg, contentType: "image/jpeg")
        return config.url.appending(path: "storage/v1/object/public/listing-photos/\(path)").absoluteString
    }

    func deletePhotos(urls: [String]) async {
        let marker = "/storage/v1/object/public/listing-photos/"
        let paths = urls.compactMap { u -> String? in
            guard let r = u.range(of: marker) else { return nil }
            return String(u[r.upperBound...])
        }
        guard !paths.isEmpty,
              let body = try? JSONSerialization.data(withJSONObject: ["prefixes": paths]) else { return }
        _ = try? await send("DELETE", "storage/v1/object/listing-photos", body: body)
    }

    // MARK: Favorites and blocks

    func fetchFavorites() async throws -> [UUID] {
        let data = try await send("GET", "rest/v1/favorites", query: [.init(name: "select", value: "listing_id")])
        return try JSON.decoder.decode([FavoriteRow].self, from: data).map(\.listingId)
    }

    func addFavorite(_ listingID: UUID) async throws {
        _ = try await send("POST", "rest/v1/favorites",
                           body: try JSONSerialization.data(withJSONObject: ["listing_id": listingID.uuidString.lowercased()]),
                           extra: ["Prefer": "return=minimal,resolution=ignore-duplicates"])
    }

    func removeFavorite(_ listingID: UUID) async throws {
        _ = try await send("DELETE", "rest/v1/favorites",
                           query: [.init(name: "listing_id", value: "eq.\(listingID.uuidString.lowercased())")])
    }

    func fetchBlocks() async throws -> [UUID] {
        let data = try await send("GET", "rest/v1/blocks", query: [.init(name: "select", value: "blocked_id")])
        return try JSON.decoder.decode([BlockRow].self, from: data).map(\.blockedId)
    }

    func block(_ userID: UUID) async throws {
        _ = try await send("POST", "rest/v1/blocks",
                           body: try JSONSerialization.data(withJSONObject: ["blocked_id": userID.uuidString.lowercased()]),
                           extra: ["Prefer": "return=minimal,resolution=ignore-duplicates"])
    }

    func report(listingID: UUID?, userID: UUID?, reason: String) async throws {
        var body: [String: String] = ["reason": reason]
        if let listingID { body["listing_id"] = listingID.uuidString.lowercased() }
        if let userID { body["reported_user_id"] = userID.uuidString.lowercased() }
        _ = try await send("POST", "rest/v1/reports", body: try JSONSerialization.data(withJSONObject: body),
                           extra: ["Prefer": "return=minimal"])
    }

    // MARK: Chat

    func fetchThreads(me: UUID) async throws -> [ChatThread] {
        let select = "id,listing_id,buyer_id,seller_id,listings!listing_id(title),buyer:profiles!buyer_id(name),seller:profiles!seller_id(name),messages(id,sender_id,body,created_at)"
        let data = try await send("GET", "rest/v1/threads", query: [
            .init(name: "select", value: select),
            .init(name: "order", value: "created_at.desc"),
        ])
        return try JSON.decoder.decode([ThreadRow].self, from: data).map { row in
            let iAmBuyer = row.buyerId == me
            let other = iAmBuyer ? row.seller : row.buyer
            return ChatThread(id: row.id, listingID: row.listingId,
                              listingTitle: row.listings?.title ?? "Listing",
                              otherName: other?.name?.isEmpty == false ? other!.name! : "User",
                              messages: row.messages.sorted { $0.createdAt < $1.createdAt }.map {
                                  ChatMessage(id: $0.id, text: $0.body, fromMe: $0.senderId == me, date: $0.createdAt)
                              },
                              otherUserID: iAmBuyer ? row.sellerId : row.buyerId)
        }
    }

    func getOrCreateThread(listing: Listing, me: UUID) async throws -> ChatThread {
        let existing = try await send("GET", "rest/v1/threads", query: [
            .init(name: "select", value: "id"),
            .init(name: "listing_id", value: "eq.\(listing.id.uuidString.lowercased())"),
            .init(name: "buyer_id", value: "eq.\(me.uuidString.lowercased())"),
        ])
        struct IDRow: Decodable { var id: UUID }
        let id: UUID
        if let found = try JSON.decoder.decode([IDRow].self, from: existing).first {
            id = found.id
        } else {
            id = UUID()
            let body = try JSONSerialization.data(withJSONObject: [
                "id": id.uuidString.lowercased(),
                "listing_id": listing.id.uuidString.lowercased(),
                "seller_id": listing.sellerID.uuidString.lowercased(),
            ])
            _ = try await send("POST", "rest/v1/threads", body: body, extra: ["Prefer": "return=minimal"])
        }
        let messages = try await fetchMessages(threadID: id, me: me)
        return ChatThread(id: id, listingID: listing.id, listingTitle: listing.title,
                          otherName: listing.sellerName, messages: messages, otherUserID: listing.sellerID)
    }

    func fetchMessages(threadID: UUID, me: UUID) async throws -> [ChatMessage] {
        let data = try await send("GET", "rest/v1/messages", query: [
            .init(name: "select", value: "id,sender_id,body,created_at"),
            .init(name: "thread_id", value: "eq.\(threadID.uuidString.lowercased())"),
            .init(name: "order", value: "created_at.asc"),
        ])
        return try JSON.decoder.decode([MessageRow].self, from: data).map {
            ChatMessage(id: $0.id, text: $0.body, fromMe: $0.senderId == me, date: $0.createdAt)
        }
    }

    func sendMessage(id: UUID, threadID: UUID, body: String) async throws {
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString.lowercased(),
            "thread_id": threadID.uuidString.lowercased(),
            "body": body,
        ])
        _ = try await send("POST", "rest/v1/messages", body: payload, extra: ["Prefer": "return=minimal"])
    }

    // MARK: Account

    func deleteAccount() async throws {
        _ = try await send("POST", "rest/v1/rpc/delete_my_account", body: Data("{}".utf8))
        setSession(nil)
    }

    // MARK: Transport

    private func send(_ method: String, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
                      contentType: String? = "application/json", extra: [String: String] = [:],
                      authed: Bool = true, retry: Bool = true) async throws -> Data {
        var token = config.anonKey
        if authed, let s = session {
            if s.expiresAt < Date().addingTimeInterval(30) { try await refresh() }
            token = session?.accessToken ?? config.anonKey
        }

        var comps = URLComponents(url: config.url.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.httpBody = body
        req.timeoutInterval = 30
        req.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil, let contentType { req.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        for (k, v) in extra { req.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await http.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, authed, retry, session != nil {
            try await refresh()
            return try await send(method, path, query: query, body: body, contentType: contentType,
                                  extra: extra, authed: authed, retry: false)
        }
        guard (200..<300).contains(status) else {
            throw BackendError.http(status, Self.message(from: data, status: status))
        }
        return data
    }

    private static func message(from data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["msg", "message", "error_description", "error"] {
                if let s = obj[key] as? String, !s.isEmpty { return s }
            }
        }
        return "Request failed (\(status))."
    }
}
