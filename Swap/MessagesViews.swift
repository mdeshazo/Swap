import SwiftUI

struct InboxView: View {
    @Environment(Store.self) private var store
    @State private var showSignIn = false

    private var sorted: [ChatThread] {
        store.threads.sorted {
            ($0.messages.last?.date ?? .distantPast) > ($1.messages.last?.date ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.usesBackend && store.currentUser == nil {
                    ContentUnavailableView {
                        Label("Sign in to see messages", systemImage: "bubble.left.and.bubble.right")
                    } actions: {
                        Button("Sign in") { showSignIn = true }.buttonStyle(.borderedProminent)
                    }
                } else if store.threads.isEmpty {
                    ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Message a seller from any listing and it shows up here."))
                } else {
                    List {
                        ForEach(sorted) { thread in
                            NavigationLink(value: thread.id) { row(thread) }
                                .swipeActions {
                                    Button("Hide", role: .destructive) { store.deleteThread(thread.id) }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await store.refresh() }
                }
            }
            .navigationTitle("Inbox")
            .navigationDestination(for: UUID.self) { ChatView(threadID: $0) }
            .sheet(isPresented: $showSignIn) { SignInView() }
        }
    }

    private func row(_ t: ChatThread) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(t.otherName).font(.headline)
                Spacer()
                if let last = t.messages.last {
                    Text(last.date, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(t.listingTitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            Text(t.messages.last?.text ?? "Say hello")
                .font(.subheadline).lineLimit(1)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

struct ChatView: View {
    let threadID: UUID
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var showReport = false
    @State private var confirmBlock = false

    private let quickReplies = ["Is this still available?", "Can you do a lower price?", "When can I pick it up?"]
    private let reportReasons = ["Spam or scam", "Harassment", "Offensive content", "Something else"]

    var body: some View {
        if let thread = store.thread(id: threadID) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 8) {
                        Text("About: \(thread.listingTitle)")
                            .font(.footnote).foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        ForEach(thread.messages) { m in
                            Bubble(message: m).id(m.id)
                        }
                        if thread.messages.isEmpty {
                            ForEach(quickReplies, id: \.self) { q in
                                Button(q) { store.send(q, in: threadID) }
                                    .buttonStyle(.bordered)
                            }
                        }
                        if !store.usesBackend {
                            Text("Demo mode: replies are simulated.")
                                .font(.caption2).foregroundStyle(.tertiary)
                                .padding(.top, 8)
                        }
                    }
                    .padding()
                }
                .onChange(of: thread.messages.count) {
                    if let last = thread.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            .navigationTitle(thread.otherName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if thread.otherUserID != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Report", systemImage: "flag") { showReport = true }
                            Button("Block", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("More")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .confirmationDialog("Why are you reporting \(thread.otherName)?",
                                isPresented: $showReport, titleVisibility: .visible) {
                ForEach(reportReasons, id: \.self) { reason in
                    Button(reason) {
                        if let other = thread.otherUserID { store.reportUser(other, reason: reason) }
                    }
                }
            }
            .confirmationDialog("Block \(thread.otherName)?",
                                isPresented: $confirmBlock, titleVisibility: .visible) {
                Button("Block", role: .destructive) {
                    if let other = thread.otherUserID { store.block(other) }
                    dismiss()
                }
            } message: {
                Text("You won't see their listings or messages.")
            }
            .task {
                // No realtime socket yet, so check for new messages every few seconds while this screen is open.
                guard store.usesBackend else { return }
                while !Task.isCancelled {
                    await store.pollMessages(threadID)
                    try? await Task.sleep(for: .seconds(4))
                }
            }
        } else {
            ContentUnavailableView("Conversation removed", systemImage: "bubble.left")
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        store.send(draft, in: threadID)
        draft = ""
    }
}

struct Bubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.fromMe { Spacer(minLength: 48) }
            Text(message.text)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(message.fromMe ? Color.accentColor : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 16))
                .foregroundStyle(message.fromMe ? Color.white : Color.primary)
            if !message.fromMe { Spacer(minLength: 48) }
        }
    }
}

#Preview {
    let store = Store(inMemory: true)
    let t = store.thread(for: store.listings[0])
    store.send("Is this still available?", in: t.id)
    return NavigationStack { ChatView(threadID: t.id) }.environment(store)
}
