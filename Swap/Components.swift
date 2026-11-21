import SwiftUI
import UIKit

enum PhotoStorage {
    private static let cache = NSCache<NSString, UIImage>()

    private static var dir: URL {
        let d = URL.documentsDirectory.appending(path: "photos")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func compressedJPEG(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, 1600 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }

    static func save(_ data: Data) -> String? {
        guard let jpeg = compressedJPEG(data) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try jpeg.write(to: dir.appending(path: name))
            return name
        } catch {
            return nil
        }
    }

    static func image(named name: String) -> UIImage? {
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let img = UIImage(contentsOfFile: dir.appending(path: name).path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }

    static func remove(_ names: [String]) {
        for n in names {
            cache.removeObject(forKey: n as NSString)
            try? FileManager.default.removeItem(at: dir.appending(path: n))
        }
    }
}

/// Fills whatever size it is given. Shows the photo, or a category placeholder.
struct ListingImage: View {
    let listing: Listing
    var index = 0

    var body: some View {
        Color(.secondarySystemBackground)
            .overlay {
                if index < listing.photoFiles.count,
                   let ui = PhotoStorage.image(named: listing.photoFiles[index]) {
                    Image(uiImage: ui)
                        .resizable()
                        .scaledToFill()
                } else if index < listing.remotePhotos.count,
                          let url = URL(string: listing.remotePhotos[index]) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .empty:
                            ProgressView()
                        default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: listing.category.symbol)
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
    }
}

struct ListingCard: View {
    @Environment(Store.self) private var store
    let listing: Listing

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ListingImage(listing: listing)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(alignment: .topTrailing) {
                    if store.saved.contains(listing.id) {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                            .padding(8)
                            .background(.thinMaterial, in: Circle())
                            .padding(6)
                    }
                }
                .overlay {
                    if listing.isSold {
                        Text("Sold")
                            .font(.headline)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                }
            Text(listing.priceText)
                .font(.headline)
            Text(listing.title)
                .font(.subheadline)
                .lineLimit(1)
            Text(listing.placeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct ListingGrid: View {
    let listings: [Listing]
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(listings) { listing in
                NavigationLink(value: listing.id) {
                    ListingCard(listing: listing)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }
}
