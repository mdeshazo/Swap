import SwiftUI

struct BrowseView: View {
    @Environment(Store.self) private var store
    @State private var query = ""
    @State private var filters = Filters()
    @State private var showFilters = false

    private var results: [Listing] {
        store.listings
            .filter { filters.matches($0, query: query) }
            .sorted(by: filters.sort.ordered)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    categoryChips
                    if results.isEmpty {
                        emptyState
                    } else {
                        ListingGrid(listings: results)
                    }
                }
                .padding(.bottom)
            }
            .navigationTitle("Swap")
            .searchable(text: $query, prompt: "Search items")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: filters.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filters")
                }
            }
            .sheet(isPresented: $showFilters) {
                FilterSheet(filters: $filters)
                    .presentationDetents([.medium, .large])
            }
            .navigationDestination(for: UUID.self) { id in
                ListingDetailView(listingID: id)
            }
            .refreshable { try? await Task.sleep(for: .milliseconds(400)) }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", symbol: "square.grid.2x2", selected: filters.category == nil) {
                    filters.category = nil
                }
                ForEach(Category.allCases) { c in
                    chip(c.title, symbol: c.symbol, selected: filters.category == c) {
                        filters.category = c
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var emptyState: some View {
        if query.isEmpty {
            ContentUnavailableView {
                Label("Nothing here yet", systemImage: "tray")
            } description: {
                Text("Try a different category or clear your filters.")
            } actions: {
                Button("Clear filters") { filters = Filters() }
            }
            .padding(.top, 40)
        } else {
            ContentUnavailableView.search(text: query)
                .padding(.top, 40)
        }
    }
}

struct FilterSheet: View {
    @Binding var filters: Filters
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Sort") {
                    Picker("Sort by", selection: $filters.sort) {
                        ForEach(Sort.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Category and condition") {
                    Picker("Category", selection: $filters.category) {
                        Text("Any").tag(Category?.none)
                        ForEach(Category.allCases) { Text($0.title).tag(Category?.some($0)) }
                    }
                    Picker("Condition", selection: $filters.condition) {
                        Text("Any").tag(Condition?.none)
                        ForEach(Condition.allCases) { Text($0.title).tag(Condition?.some($0)) }
                    }
                }
                Section("Price") {
                    HStack {
                        TextField("Min", value: $filters.minPrice, format: .number)
                        Text("to").foregroundStyle(.secondary)
                        TextField("Max", value: $filters.maxPrice, format: .number)
                    }
                    .keyboardType(.decimalPad)
                }
                Section("Distance") {
                    VStack(alignment: .leading) {
                        Text(filters.maxDistance >= 100 ? "Any distance" : "Within \(Int(filters.maxDistance)) miles")
                        Slider(value: $filters.maxDistance, in: 1...100, step: 1)
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") { filters = Filters() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.bold()
                }
            }
        }
    }
}

#Preview {
    BrowseView().environment(Store(inMemory: true))
}
