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
            .refreshable { await store.refresh() }
        }
    }
}

struct ProfileView: View {
    @Environment(Store.self) private var store
    @State private var showSignIn = false
    @State private var confirmSignOut = false
    @State private var confirmDeleteAccount = false

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
                            Button("Delete account", role: .destructive) { confirmDeleteAccount = true }
                        } footer: {
                            Text("Deleting your account removes your listings, messages, and saved items.")
                        }
                    }
                } else {
                    ContentUnavailableView {
                        Label("Join Swap", systemImage: "person.crop.circle")
                    } description: {
                        Text("Create a free account to sell items and message sellers.")
                    } actions: {
                        Button("Sign in or create account") { showSignIn = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                #if DEBUG
                if UserDefaults.standard.bool(forKey: "showSignIn") { showSignIn = true }
                #endif
            }
            .navigationDestination(for: UUID.self) { ListingDetailView(listingID: $0) }
            .sheet(isPresented: $showSignIn) { SignInView() }
            .confirmationDialog("Sign out of Swap?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) { store.signOut() }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task {
                        do { try await store.deleteAccount() } catch { store.show(error) }
                    }
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}

struct SignInView: View {
    var onDone: (() -> Void)?
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorText: String?
    @FocusState private var focus: Field?
    private enum Field { case name, email, password }

    private var valid: Bool {
        email.contains("@") && email.contains(".")
            && (!creating || !name.trimmingCharacters(in: .whitespaces).isEmpty)
            && (!store.usesBackend || password.count >= 8)
    }

    var body: some View {
        NavigationStack {
            Form {
                if store.usesBackend {
                    Picker("Mode", selection: $creating) {
                        Text("Create account").tag(true)
                        Text("Sign in").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                }
                if store.usesBackend {
                    Section {
                        Button {
                            google()
                        } label: {
                            Label("Continue with Google", systemImage: "g.circle.fill")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .disabled(busy)
                    } footer: {
                        Text("Or use your email below.")
                    }
                }
                Section {
                    if creating {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                            .focused($focus, equals: .name)
                            .submitLabel(.next)
                            .onSubmit { focus = .email }
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(store.usesBackend ? .next : .done)
                        .onSubmit { if store.usesBackend { focus = .password } }
                    if store.usesBackend {
                        SecureField("Password (8 or more characters)", text: $password)
                            .textContentType(creating ? .newPassword : .password)
                            .focused($focus, equals: .password)
                            .submitLabel(.done)
                            .onSubmit(submit)
                    }
                } footer: {
                    if !store.usesBackend { Text("Demo account. Stored on this device only.") }
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle(creating ? "Create account" : "Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if busy {
                        ProgressView()
                    } else {
                        Button("Continue", action: submit).bold().disabled(!valid)
                    }
                }
            }
            .onAppear { focus = creating ? .name : .email }
        }
        .presentationDetents([.medium, .large])
    }

    private func google() {
        guard !busy else { return }
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                try await store.signInWithGoogle()
                dismiss()
                onDone?()
            } catch is CancellationError {
                // The person closed the Google sheet. Nothing to show.
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func submit() {
        guard valid, !busy else { return }
        busy = true
        errorText = nil
        Task {
            defer { busy = false }
            do {
                if creating {
                    try await store.signUp(name: name, email: email, password: password)
                } else {
                    try await store.signIn(email: email, password: password)
                }
                dismiss()
                onDone?()
            } catch {
                errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

#Preview {
    ProfileView().environment(Store(inMemory: true))
}
