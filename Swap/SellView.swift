import SwiftUI
import PhotosUI

struct SellView: View {
    @Environment(Store.self) private var store
    @State private var title = ""
    @State private var priceText = ""
    @State private var category: Category = .other
    @State private var condition: Condition = .good
    @State private var details = ""
    @State private var location = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var photoData: [Data] = []
    @State private var showSignIn = false
    @State private var showPosted = false
    @State private var isPosting = false

    private var price: Double? {
        let cleaned = priceText.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard let v = Double(cleaned), v >= 0 else { return nil }
        return v
    }

    private var canPost: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && price != nil
            && !location.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Photos") {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                        Label(photoData.isEmpty ? "Add photos" : "Change photos",
                              systemImage: "photo.on.rectangle.angled")
                    }
                    if !photoData.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Array(photoData.enumerated()), id: \.offset) { _, data in
                                    if let ui = UIImage(data: data) {
                                        Image(uiImage: ui)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                }
                Section("Details") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                    TextField("Price (0 for free)", text: $priceText)
                        .keyboardType(.decimalPad)
                    Picker("Category", selection: $category) {
                        ForEach(Category.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Condition", selection: $condition) {
                        ForEach(Condition.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Description") {
                    TextEditor(text: $details)
                        .frame(minHeight: 100)
                }
                Section("Location") {
                    TextField("Neighborhood or city", text: $location)
                }
                Section {
                    Button {
                        post()
                    } label: {
                        if isPosting {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Post listing").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canPost || isPosting)
                } footer: {
                    if store.currentUser == nil {
                        Text("You'll create a free account when you post.")
                    }
                }
            }
            .navigationTitle("Sell an item")
            .onChange(of: pickerItems) { _, items in
                Task {
                    var out: [Data] = []
                    for item in items {
                        if let d = try? await item.loadTransferable(type: Data.self) { out.append(d) }
                    }
                    photoData = out
                }
            }
            .sheet(isPresented: $showSignIn) {
                SignInView { post() }
            }
            .alert("Listing posted", isPresented: $showPosted) {
                Button("View in Browse") { store.selectedTab = .browse }
                Button("OK", role: .cancel) {}
            }
        }
    }

    private func post() {
        guard canPost, let price, !isPosting else { return }
        guard store.currentUser != nil else {
            showSignIn = true
            return
        }
        isPosting = true
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)
        let cleanDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location.trimmingCharacters(in: .whitespaces)
        let photos = photoData
        let cat = category, cond = condition
        Task {
            defer { isPosting = false }
            do {
                try await store.addListing(title: cleanTitle, price: price, category: cat, condition: cond,
                                           details: cleanDetails, location: cleanLocation, photos: photos)
                title = ""; priceText = ""; details = ""; location = ""
                category = .other; condition = .good
                pickerItems = []; photoData = []
                showPosted = true
            } catch {
                store.show(error)
            }
        }
    }
}

#Preview {
    SellView().environment(Store(inMemory: true))
}
