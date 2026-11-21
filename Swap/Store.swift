import SwiftUI

@MainActor
@Observable
final class Store {
    var listings: [Listing] = []
    var saved: Set<UUID> = []
    var threads: [ChatThread] = []
    var account: User?
    var isSignedIn = false
    var selectedTab: AppTab = .browse
    var errorMessage: String?
    var noticeMessage: String?
    var blocked: Set<UUID> = []

    /// nil means demo mode: everything stays on this device.
    @ObservationIgnored let backend: SupabaseClient?
    @ObservationIgnored private let persist: Bool
    @ObservationIgnored private let fileURL: URL

    var usesBackend: Bool { backend != nil }
    var currentUser: User? { isSignedIn ? account : nil }

    private struct Snapshot: Codable {
        var listings: [Listing]
        var saved: [UUID]
        var threads: [ChatThread]
        var account: User?
        var isSignedIn: Bool
    }

    init(inMemory: Bool = false) {
        let client = inMemory ? nil : Backend.makeClient()
        backend = client
        persist = !inMemory && client == nil
        fileURL = URL.documentsDirectory.appending(path: "swap-data.json")

        if backend != nil {
            Task {
                await restoreSession()
                await refresh()
            }
        } else if persist, let data = try? Data(contentsOf: fileURL),
                  let snap = try? JSONDecoder().decode(Snapshot.self, from: data) {
            listings = snap.listings
            saved = Set(snap.saved)
            threads = snap.threads
            account = snap.account
            isSignedIn = snap.isSignedIn
        } else {
            listings = Store.seedListings()
            if persist { save() }
        }
    }

    private func save() {
        guard persist else { return }
        let snap = Snapshot(listings: listings, saved: Array(saved), threads: threads,
                            account: account, isSignedIn: isSignedIn)
        if let data = try? JSONEncoder().encode(snap) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func show(_ error: Error) {
        if error is CancellationError { return }
        if let u = error as? URLError, u.code == .cancelled { return }
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: Sync

    private func restoreSession() async {
        guard let backend, let s = await backend.session else { return }
        account = User(id: s.userID, name: s.name, email: s.email)
        isSignedIn = true
    }

    func refresh() async {
        guard let backend else { return }
        do {
            let rows = try await backend.fetchListings()
            var favs: [UUID] = []
            var blk: [UUID] = []
            var ths: [ChatThread] = []
            if let me = currentUser {
                blk = try await backend.fetchBlocks()
                favs = try await backend.fetchFavorites()
                ths = try await backend.fetchThreads(me: me.id)
            }
            let blockedSet = Set(blk)
            blocked = blockedSet
            listings = rows.map { $0.toListing() }.filter { !blockedSet.contains($0.sellerID) }
            saved = Set(favs)
            threads = ths.filter { !blockedSet.contains($0.otherUserID ?? UUID()) }
        } catch {
            show(error)
        }
    }

    // MARK: Account

    /// Demo mode ignores the password. Backend mode creates a real account.
    func signUp(name: String, email: String, password: String = "") async throws {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        let cleanEmail = email.trimmingCharacters(in: .whitespaces)
        if let backend {
            let s = try await backend.signUp(name: cleanName, email: cleanEmail, password: password)
            account = User(id: s.userID, name: s.name, email: s.email)
            isSignedIn = true
            await refresh()
        } else {
            let id = (account?.email.lowercased() == cleanEmail.lowercased() ? account?.id : nil) ?? UUID()
            account = User(id: id, name: cleanName, email: cleanEmail)
            isSignedIn = true
            save()
        }
    }

    func signIn(email: String, password: String) async throws {
        guard let backend else { return }
        let s = try await backend.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
        account = User(id: s.userID, name: s.name, email: s.email)
        isSignedIn = true
        await refresh()
    }

    func signOut() {
        if let backend { Task { await backend.signOut() } }
        isSignedIn = false
        selectedTab = .browse
        if usesBackend {
            account = nil
            saved = []
            threads = []
            blocked = []
        }
        save()
    }

    func deleteAccount() async throws {
        if let backend {
            let mine = myListings
            for l in mine { await backend.deletePhotos(urls: l.remotePhotos) }
            try await backend.deleteAccount()
            account = nil
            isSignedIn = false
            saved = []
            threads = []
            blocked = []
            selectedTab = .browse
            await refresh()
        } else {
            let id = currentUser?.id
            listings.removeAll { $0.sellerID == id }
            account = nil
            isSignedIn = false
            selectedTab = .browse
            save()
        }
    }

    // MARK: Listings

    func listing(_ id: UUID) -> Listing? {
        listings.first { $0.id == id }
    }

    func isMine(_ listing: Listing) -> Bool {
        currentUser?.id == listing.sellerID
    }

    var myListings: [Listing] {
        guard let id = currentUser?.id else { return [] }
        return listings.filter { $0.sellerID == id }.sorted { $0.createdAt > $1.createdAt }
    }

    var savedListings: [Listing] {
        listings.filter { saved.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
    }

    func addListing(title: String, price: Double, category: Category, condition: Condition,
                    details: String, location: String, photos: [Data]) async throws {
        guard let user = currentUser else { return }
        if let backend {
            let id = UUID()
            var urls: [String] = []
            do {
                for data in photos {
                    guard let jpeg = PhotoStorage.compressedJPEG(data) else { continue }
                    urls.append(try await backend.uploadPhoto(jpeg))
                }
                try await backend.createListing(id: id, title: title, price: price, category: category,
                                                condition: condition, details: details, location: location,
                                                photoURLs: urls)
            } catch {
                await backend.deletePhotos(urls: urls)
                throw error
            }
            listings.insert(Listing(id: id, title: title, price: price, category: category, condition: condition,
                                    details: details, locationName: location, distanceMiles: 0,
                                    sellerID: user.id, sellerName: user.name, photoURLs: urls), at: 0)
        } else {
            let files = photos.compactMap { PhotoStorage.save($0) }
            listings.insert(Listing(title: title, price: price, category: category, condition: condition,
                                    details: details, locationName: location, distanceMiles: 0,
                                    sellerID: user.id, sellerName: user.name, photoFiles: files), at: 0)
            save()
        }
    }

    func toggleSaved(_ id: UUID) {
        if usesBackend && currentUser == nil {
            errorMessage = "Sign in to save items."
            return
        }
        let nowSaved = !saved.contains(id)
        if nowSaved { saved.insert(id) } else { saved.remove(id) }
        save()
        guard let backend else { return }
        Task {
            do {
                if nowSaved { try await backend.addFavorite(id) } else { try await backend.removeFavorite(id) }
            } catch {
                if nowSaved { saved.remove(id) } else { saved.insert(id) }
                show(error)
            }
        }
    }

    func markSold(_ id: UUID) {
        guard let i = listings.firstIndex(where: { $0.id == id }) else { return }
        listings[i].isSold = true
        save()
        guard let backend else { return }
        Task {
            do { try await backend.markSold(id) } catch {
                if let j = listings.firstIndex(where: { $0.id == id }) { listings[j].isSold = false }
                show(error)
            }
        }
    }

    func delete(_ id: UUID) {
        guard let i = listings.firstIndex(where: { $0.id == id }) else { return }
        let removed = listings[i]
        listings.remove(at: i)
        saved.remove(id)
        if let backend {
            Task {
                do {
                    try await backend.deleteListing(id)
                    await backend.deletePhotos(urls: removed.remotePhotos)
                } catch {
                    listings.insert(removed, at: min(i, listings.count))
                    show(error)
                }
            }
        } else {
            PhotoStorage.remove(removed.photoFiles)
            save()
        }
    }

    // MARK: Moderation

    func report(listing: Listing, reason: String) {
        file(reason: reason, listingID: listing.id, userID: listing.sellerID)
    }

    func reportUser(_ userID: UUID, reason: String) {
        file(reason: reason, listingID: nil, userID: userID)
    }

    private func file(reason: String, listingID: UUID?, userID: UUID?) {
        guard let backend else {
            noticeMessage = "Thanks. Reports are only sent in the full version."
            return
        }
        guard currentUser != nil else {
            errorMessage = "Sign in to send a report."
            return
        }
        Task {
            do {
                try await backend.report(listingID: listingID, userID: userID, reason: reason)
                noticeMessage = "Thanks. We'll review this."
            } catch {
                show(error)
            }
        }
    }

    func block(_ userID: UUID) {
        guard let backend else {
            removeLocally(userID)
            return
        }
        guard currentUser != nil else {
            errorMessage = "Sign in to block someone."
            return
        }
        Task {
            do {
                try await backend.block(userID)
                removeLocally(userID)
                noticeMessage = "Blocked. You won't see their listings or messages."
            } catch {
                show(error)
            }
        }
    }

    private func removeLocally(_ userID: UUID) {
        blocked.insert(userID)
        listings.removeAll { $0.sellerID == userID }
        threads.removeAll { $0.otherUserID == userID }
        save()
    }

    // MARK: Chat

    func thread(id: UUID) -> ChatThread? {
        threads.first { $0.id == id }
    }

    /// Local only. Used by demo mode and previews.
    func thread(for listing: Listing) -> ChatThread {
        if let existing = threads.first(where: { $0.listingID == listing.id }) { return existing }
        let t = ChatThread(listingID: listing.id, listingTitle: listing.title, otherName: listing.sellerName,
                           otherUserID: listing.sellerID)
        threads.append(t)
        save()
        return t
    }

    func openThread(for listing: Listing) async throws -> UUID {
        if let existing = threads.first(where: { $0.listingID == listing.id }) { return existing.id }
        if let backend, let me = currentUser {
            let t = try await backend.getOrCreateThread(listing: listing, me: me.id)
            threads.append(t)
            return t.id
        }
        return thread(for: listing).id
    }

    func deleteThread(_ id: UUID) {
        // The server keeps the conversation for the other person. This hides it here only.
        threads.removeAll { $0.id == id }
        save()
    }

    func pollMessages(_ threadID: UUID) async {
        guard let backend, let me = currentUser,
              let msgs = try? await backend.fetchMessages(threadID: threadID, me: me.id),
              let i = threads.firstIndex(where: { $0.id == threadID }) else { return }
        if threads[i].messages.map(\.id) != msgs.map(\.id) { threads[i].messages = msgs }
    }

    func send(_ text: String, in threadID: UUID) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = threads.firstIndex(where: { $0.id == threadID }) else { return }
        let message = ChatMessage(text: clean, fromMe: true)
        threads[i].messages.append(message)
        save()

        if let backend {
            Task {
                do {
                    try await backend.sendMessage(id: message.id, threadID: threadID, body: clean)
                } catch {
                    if let j = threads.firstIndex(where: { $0.id == threadID }) {
                        threads[j].messages.removeAll { $0.id == message.id }
                    }
                    show(error)
                }
            }
            return
        }

        // Demo mode: there is no server, so the other person's replies are canned.
        let replies = ["Yes, still available.", "Sure, when works for you?",
                       "I can do a little lower. What's your offer?", "Thanks for asking. Happy to meet in a public spot."]
        Task {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.5...3)))
            guard let j = threads.firstIndex(where: { $0.id == threadID }) else { return }
            threads[j].messages.append(ChatMessage(text: replies.randomElement() ?? "Sounds good.", fromMe: false))
            save()
        }
    }

    // MARK: Seed data (demo mode)

    private static func seedListings() -> [Listing] {
        let dana = (UUID(), "Dana"), marcus = (UUID(), "Marcus"), priya = (UUID(), "Priya"), luis = (UUID(), "Luis")
        func hours(_ h: Double) -> Date { Date().addingTimeInterval(-h * 3600) }
        return [
            Listing(title: "Standing desk, adjustable", price: 180, category: .furniture, condition: .likeNew,
                    details: "48 inch electric standing desk. Memory presets work great. Moving, must go.",
                    locationName: "Tempe", distanceMiles: 4, sellerID: dana.0, sellerName: dana.1, createdAt: hours(2)),
            Listing(title: "Road bike, 56cm", price: 425, category: .sports, condition: .good,
                    details: "Aluminum frame, recent tune up. Includes pedals and a bottle cage.",
                    locationName: "Scottsdale", distanceMiles: 9, sellerID: marcus.0, sellerName: marcus.1, createdAt: hours(5)),
            Listing(title: "iPhone 13, 128GB", price: 320, category: .electronics, condition: .good,
                    details: "Unlocked. Battery health is solid. Comes with case and charger.",
                    locationName: "Phoenix", distanceMiles: 6, sellerID: priya.0, sellerName: priya.1, createdAt: hours(8)),
            Listing(title: "Leather sofa, 3 seater", price: 275, category: .furniture, condition: .good,
                    details: "Comfortable and clean. Pet free, smoke free home. You haul.",
                    locationName: "Mesa", distanceMiles: 14, sellerID: luis.0, sellerName: luis.1, createdAt: hours(12)),
            Listing(title: "Kids wooden train set", price: 0, category: .toys, condition: .fair,
                    details: "Free to a good home. Most pieces included.",
                    locationName: "Chandler", distanceMiles: 18, sellerID: dana.0, sellerName: dana.1, createdAt: hours(20)),
            Listing(title: "Carhartt jacket, size L", price: 60, category: .clothing, condition: .likeNew,
                    details: "Worn twice. Brown duck canvas, blanket lined.",
                    locationName: "Glendale", distanceMiles: 22, sellerID: marcus.0, sellerName: marcus.1, createdAt: hours(30)),
            Listing(title: "Toyota Camry 2012", price: 6900, category: .vehicles, condition: .good,
                    details: "142k miles. Clean title. Recent brakes and tires. Cash only.",
                    locationName: "Gilbert", distanceMiles: 25, sellerID: luis.0, sellerName: luis.1, createdAt: hours(40)),
            Listing(title: "Air fryer, 5 quart", price: 35, category: .home, condition: .likeNew,
                    details: "Used a handful of times. Basket is nonstick and spotless.",
                    locationName: "Peoria", distanceMiles: 27, sellerID: priya.0, sellerName: priya.1, createdAt: hours(52)),
        ]
    }
}
