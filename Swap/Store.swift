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

    @ObservationIgnored private let persist: Bool
    @ObservationIgnored private let fileURL: URL

    var currentUser: User? { isSignedIn ? account : nil }

    private struct Snapshot: Codable {
        var listings: [Listing]
        var saved: [UUID]
        var threads: [ChatThread]
        var account: User?
        var isSignedIn: Bool
    }

    init(inMemory: Bool = false) {
        persist = !inMemory
        fileURL = URL.documentsDirectory.appending(path: "swap-data.json")
        if persist, let data = try? Data(contentsOf: fileURL),
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

    // MARK: Account

    func signUp(name: String, email: String) {
        let cleanEmail = email.trimmingCharacters(in: .whitespaces)
        let id = (account?.email.lowercased() == cleanEmail.lowercased() ? account?.id : nil) ?? UUID()
        account = User(id: id, name: name.trimmingCharacters(in: .whitespaces), email: cleanEmail)
        isSignedIn = true
        save()
    }

    func signOut() {
        isSignedIn = false
        selectedTab = .browse
        save()
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
                    details: String, location: String, photos: [Data]) {
        guard let user = currentUser else { return }
        let files = photos.compactMap { PhotoStorage.save($0) }
        let listing = Listing(title: title, price: price, category: category, condition: condition,
                              details: details, locationName: location, distanceMiles: 0,
                              sellerID: user.id, sellerName: user.name, photoFiles: files)
        listings.insert(listing, at: 0)
        save()
    }

    func toggleSaved(_ id: UUID) {
        if saved.contains(id) { saved.remove(id) } else { saved.insert(id) }
        save()
    }

    func markSold(_ id: UUID) {
        guard let i = listings.firstIndex(where: { $0.id == id }) else { return }
        listings[i].isSold = true
        save()
    }

    func delete(_ id: UUID) {
        guard let i = listings.firstIndex(where: { $0.id == id }) else { return }
        PhotoStorage.remove(listings[i].photoFiles)
        listings.remove(at: i)
        saved.remove(id)
        save()
    }

    // MARK: Chat

    func thread(id: UUID) -> ChatThread? {
        threads.first { $0.id == id }
    }

    func thread(for listing: Listing) -> ChatThread {
        if let existing = threads.first(where: { $0.listingID == listing.id }) { return existing }
        let t = ChatThread(listingID: listing.id, listingTitle: listing.title, otherName: listing.sellerName)
        threads.append(t)
        save()
        return t
    }

    func deleteThread(_ id: UUID) {
        threads.removeAll { $0.id == id }
        save()
    }

    /// Demo mode: there is no server, so the other person's replies are canned.
    func send(_ text: String, in threadID: UUID) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let i = threads.firstIndex(where: { $0.id == threadID }) else { return }
        threads[i].messages.append(ChatMessage(text: clean, fromMe: true))
        save()
        let replies = ["Yes, still available.", "Sure, when works for you?",
                       "I can do a little lower. What's your offer?", "Thanks for asking. Happy to meet in a public spot."]
        Task {
            try? await Task.sleep(for: .seconds(Double.random(in: 1.5...3)))
            guard let j = threads.firstIndex(where: { $0.id == threadID }) else { return }
            threads[j].messages.append(ChatMessage(text: replies.randomElement() ?? "Sounds good.", fromMe: false))
            save()
        }
    }

    // MARK: Seed data

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
