import Foundation

enum Category: String, CaseIterable, Codable, Identifiable {
    case electronics, furniture, vehicles, clothing, home, sports, toys, other

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .electronics: return "iphone"
        case .furniture: return "chair.lounge"
        case .vehicles: return "car"
        case .clothing: return "tshirt"
        case .home: return "house"
        case .sports: return "figure.run"
        case .toys: return "teddybear"
        case .other: return "tag"
        }
    }
}

enum Condition: String, CaseIterable, Codable, Identifiable {
    case new, likeNew, good, fair

    var id: String { rawValue }
    var title: String {
        switch self {
        case .new: return "New"
        case .likeNew: return "Like new"
        case .good: return "Good"
        case .fair: return "Fair"
        }
    }
}

struct User: Codable, Equatable {
    var id: UUID
    var name: String
    var email: String
}

struct Listing: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var price: Double
    var category: Category
    var condition: Condition
    var details: String
    var locationName: String
    var distanceMiles: Double
    var sellerID: UUID
    var sellerName: String
    var photoFiles: [String] = []
    var photoURLs: [String]? = nil
    var createdAt = Date()
    var isSold = false

    var priceText: String {
        if price == 0 { return "Free" }
        return price.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
    }

    var remotePhotos: [String] { photoURLs ?? [] }
    var photoCount: Int { max(photoFiles.count, remotePhotos.count) }

    /// Empty when the distance is unknown (real backend listings have no location yet).
    var distanceText: String {
        if distanceMiles <= 0 { return "" }
        return distanceMiles < 1 ? "Nearby" : "\(Int(distanceMiles.rounded())) mi"
    }

    var placeText: String {
        distanceText.isEmpty ? locationName : "\(locationName) · \(distanceText)"
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var fromMe: Bool
    var date = Date()
}

struct ChatThread: Identifiable, Codable, Hashable {
    var id = UUID()
    var listingID: UUID
    var listingTitle: String
    var otherName: String
    var messages: [ChatMessage] = []
    var otherUserID: UUID? = nil
}

enum Sort: String, CaseIterable, Identifiable {
    case newest, priceLow, priceHigh, closest

    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: return "Newest"
        case .priceLow: return "Price: low to high"
        case .priceHigh: return "Price: high to low"
        case .closest: return "Closest"
        }
    }

    func ordered(_ a: Listing, _ b: Listing) -> Bool {
        switch self {
        case .newest: return a.createdAt > b.createdAt
        case .priceLow: return a.price < b.price
        case .priceHigh: return a.price > b.price
        case .closest: return a.distanceMiles < b.distanceMiles
        }
    }
}

struct Filters: Equatable {
    var category: Category?
    var condition: Condition?
    var minPrice: Double?
    var maxPrice: Double?
    var maxDistance: Double = 100
    var sort: Sort = .newest

    var isActive: Bool {
        category != nil || condition != nil || minPrice != nil || maxPrice != nil
            || maxDistance < 100 || sort != .newest
    }

    func matches(_ l: Listing, query: String) -> Bool {
        guard !l.isSold else { return false }
        if let category, l.category != category { return false }
        if let condition, l.condition != condition { return false }
        if let minPrice, l.price < minPrice { return false }
        if let maxPrice, l.price > maxPrice { return false }
        if l.distanceMiles > maxDistance { return false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty,
           !(l.title.localizedCaseInsensitiveContains(q) || l.details.localizedCaseInsensitiveContains(q)) {
            return false
        }
        return true
    }
}
