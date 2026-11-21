import SwiftUI

@main
struct SwapApp: App {
    @State private var store = Store()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

enum AppTab: Hashable {
    case browse, sell, inbox, saved, profile
}

struct RootView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.selectedTab) {
            BrowseView()
                .tabItem { Label("Browse", systemImage: "magnifyingglass") }
                .tag(AppTab.browse)
            SellView()
                .tabItem { Label("Sell", systemImage: "plus.circle.fill") }
                .tag(AppTab.sell)
            InboxView()
                .tabItem { Label("Inbox", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.inbox)
            SavedView()
                .tabItem { Label("Saved", systemImage: "heart") }
                .tag(AppTab.saved)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert("Done", isPresented: Binding(
            get: { store.noticeMessage != nil },
            set: { if !$0 { store.noticeMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.noticeMessage ?? "")
        }
    }
}

#Preview {
    RootView().environment(Store(inMemory: true))
}
