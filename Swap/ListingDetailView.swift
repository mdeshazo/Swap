import SwiftUI

private let reportReasons = ["Spam or scam", "Prohibited item", "Offensive content", "Something else"]

struct ListingDetailView: View {
    let listingID: UUID
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var openThread: UUID?
    @State private var showSignIn = false
    @State private var confirmDelete = false
    @State private var showReport = false
    @State private var confirmBlock = false
    @State private var isOpeningChat = false

    var body: some View {
        if let listing = store.listing(listingID) {
            content(listing)
        } else {
            ContentUnavailableView("Listing removed", systemImage: "tag.slash",
                                   description: Text("This item is no longer available."))
        }
    }

    private func content(_ listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TabView {
                    ForEach(0..<max(1, listing.photoCount), id: \.self) { i in
                        ListingImage(listing: listing, index: i)
                    }
                }
                .tabViewStyle(.page)
                .frame(height: 360)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(listing.priceText).font(.title).bold()
                        if listing.isSold {
                            Text("Sold")
                                .font(.subheadline.bold())
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground), in: Capsule())
                        }
                    }
                    Text(listing.title).font(.title3)
                    Text("\(listing.condition.title) · \(listing.category.title)")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("\(listing.placeText) · Posted \(listing.createdAt.formatted(.relative(presentation: .named)))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if !listing.details.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description").font(.headline)
                        Text(listing.details)
                    }
                    .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Text(String(listing.sellerName.prefix(1)).uppercased())
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.opacity(0.15), in: Circle())
                    VStack(alignment: .leading) {
                        Text(listing.sellerName).font(.headline)
                        Text("Seller").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .accessibilityElement(children: .combine)

                Label("Meet in a public place and check the item before you pay.",
                      systemImage: "shield.lefthalf.filled")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: "\(listing.title) for \(listing.priceText) on Swap")
            }
            if !store.isMine(listing) {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Report listing", systemImage: "flag") { showReport = true }
                        Button("Block seller", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .safeAreaInset(edge: .bottom) { actionBar(listing) }
        .navigationDestination(item: $openThread) { id in ChatView(threadID: id) }
        .sheet(isPresented: $showSignIn) { SignInView() }
        .confirmationDialog("Delete this listing?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete listing", role: .destructive) {
                store.delete(listing.id)
                dismiss()
            }
        }
        .confirmationDialog("Why are you reporting this?", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(reportReasons, id: \.self) { reason in
                Button(reason) { store.report(listing: listing, reason: reason) }
            }
        }
        .confirmationDialog("Block \(listing.sellerName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                store.block(listing.sellerID)
                dismiss()
            }
        } message: {
            Text("You won't see their listings or messages.")
        }
    }

    @ViewBuilder
    private func actionBar(_ listing: Listing) -> some View {
        HStack(spacing: 12) {
            if store.isMine(listing) {
                if !listing.isSold {
                    Button("Mark as sold") { store.markSold(listing.id) }
                        .buttonStyle(.borderedProminent)
                }
                Button("Delete", role: .destructive) { confirmDelete = true }
                    .buttonStyle(.bordered)
            } else {
                Button {
                    if store.usesBackend && store.currentUser == nil {
                        showSignIn = true
                    } else {
                        store.toggleSaved(listing.id)
                    }
                } label: {
                    Image(systemName: store.saved.contains(listing.id) ? "heart.fill" : "heart")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(store.saved.contains(listing.id) ? .red : .accentColor)
                .accessibilityLabel(store.saved.contains(listing.id) ? "Remove from saved" : "Save")

                Button {
                    message(listing)
                } label: {
                    Group {
                        if isOpeningChat { ProgressView() } else { Text("Message seller") }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(listing.isSold || isOpeningChat)
            }
        }
        .padding()
        .background(.bar)
    }

    private func message(_ listing: Listing) {
        guard store.currentUser != nil else {
            showSignIn = true
            return
        }
        isOpeningChat = true
        Task {
            defer { isOpeningChat = false }
            do {
                openThread = try await store.openThread(for: listing)
            } catch {
                store.show(error)
            }
        }
    }
}

#Preview {
    let store = Store(inMemory: true)
    return NavigationStack { ListingDetailView(listingID: store.listings[0].id) }
        .environment(store)
}
