import SwiftUI

enum SidebarItem: String, Hashable {
    case library, browse, favorites, recentlyPlayed
}

struct ContentView: View {
    @Environment(LibraryStore.self) var library
    @State private var selection: SidebarItem = .library
    @State private var showAddURL = false
    @State private var showSearch = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $selection, showAddURL: $showAddURL)
                    .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            } detail: {
                ZStack {
                    Color.vgBg.ignoresSafeArea()
                    switch selection {
                    case .library:       LibraryView()
                    case .favorites:     FavoritesView()
                    case .browse:        BrowseView()
                    case .recentlyPlayed: RecentlyPlayedView()
                    }
                }
            }
            .navigationSplitViewStyle(.balanced)

            Divider().overlay(Color.vgSeparator)
            PlayerBarView()
        }
        .background(Color.vgBg)
        .sheet(isPresented: $showAddURL) {
            AddURLView(isPresented: $showAddURL)
        }
        .overlay {
            if showSearch {
                SearchOverlay(isShowing: $showSearch)
            }
        }
        .onAppear { Task { await library.load() } }
        .keyboardShortcut("k", modifiers: .command)  // ⌘K → search handled via button
    }
}
