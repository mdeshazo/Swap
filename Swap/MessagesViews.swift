import SwiftUI

struct InboxView: View {
    @Environment(Store.self) private var store

    private var sorted: [ChatThread] {
        store.threads.sorted {
            ($0.messages.last?.date ?? .distantPast) > ($1.messages.last?.date ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.threads.isEmpty {
                    ContentUnavailableView("No messages yet", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("Message a seller from any listing and it shows up here."))
                } else {
                    List {
                        ForEach(sorted) { thread in
                            NavigationLink(value: thread.id) { row(thread) }
                                .swipeActions {
                                    Button("Delete", role: .destructive) { store.deleteThread(thread.id) }
                                }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Inbox")
            .navigationDestination(for: UUID.self) { ChatView(threadID: $0) }
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
    @State private var draft = ""

    private let quickReplies = ["Is this still available?", "Can you do a lower price?", "When can I pick it up?"]

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
                        Text("Demo mode: replies are simulated.")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .padding(.top, 8)
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
            .safeAreaInset(edge: .bottom) { inputBar }
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
