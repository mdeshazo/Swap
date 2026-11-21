import SwiftUI

struct SavedView: View {
    @Environment(Store.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.savedListings.isEmpty {
                    ContentUnavailableView("Nothing saved", systemImage: "heart",
                                           description: Text("Tap the heart on a listing to keep it here."))
                        .padding(.top, 60)
                } else {
                    ListingGrid(listings: store.savedListings).padding(.vertical)
                }
            }
            .navigationTitle("Saved")
            .navigationDestination(for: UUID.self) { ListingDetailView(listingID: $0) }
        }
    }
}

struct ProfileView: View {
    @Environment(Store.self) private var store
    @State private var showSignIn = false
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Group {
                if let user = store.currentUser {
                    List {
                        Section("Account") {
                            LabeledContent("Name", value: user.name)
                            LabeledContent("Email", value: user.email)
                        }
                        Section("My listings") {
                            if store.myListings.isEmpty {
                                Text("You haven't posted anything yet.").foregroundStyle(.secondary)
                            }
                            ForEach(store.myListings) { l in
                                NavigationLink(value: l.id) {
                                    HStack {
                                        ListingImage(listing: l)
                                            .frame(width: 52, height: 52)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading) {
                                            Text(l.title).lineLimit(1)
                                            Text(l.isSold ? "Sold" : l.priceText)
                                                .font(.footnote).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .swipeActions {
                                    Button("Delete", role: .destructive) { store.delete(l.id) }
                                }
                            }
                        }
                        Section {
                            Button("Sign out", role: .destructive) { confirmSignOut = true }
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Join Swap", systemImage: "person.crop.circle")
                    } description: {
                        Text("Create a free account to sell items and message sellers.")
                    } actions: {
                        Button("Create account") { showSignIn = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationDestination(for: UUID.self) { ListingDetailView(listingID: $0) }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .confirmationDialog("Sign out of Swap?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { store.signOut() }
            }
        }
    }
}

struct SignInView: View {
    var onDone: (() -> Void)?
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @FocusState private var focus: Field?
    private enum Field { case name, email }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && email.contains("@") && email.contains(".")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                        .focused($focus, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focus = .email }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.done)
                } footer: {
                    Text("Demo account. Stored on this device only.")
                }
            }
            .navigationTitle("Create account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue") {
                        store.signUp(name: name, email: email)
                        dismiss()
                        onDone?()
                    }
                    .bold()
                    .disabled(!valid)
                }
            }
            .onAppear { focus = .name }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ProfileView().environment(Store(inMemory: true))
}
