import SwiftUI

enum SidebarItem: String, Hashable {
    case library, browse, favorites, recentlyPlayed
}

struct ContentView: View {
    @Environment(LibraryStore.self) var library
    @Environment(PlayerService.self) var player
    @State private var selection: SidebarItem = .library
    @State private var showAddURL = false
    @State private var showSearch = false

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                SidebarView(selection: $selection, showAddURL: $showAddURL)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 220)
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
        .overlay {
            if showAddURL {
                ZStack {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { showAddURL = false }
                    AddURLView(isPresented: $showAddURL)
                }
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onKeyPress(.escape) { showAddURL = false; return .handled }
            }
        }
        .overlay {
            if showSearch {
                SearchOverlay(isShowing: $showSearch)
            }
        }
        .onAppear { Task { await library.load() } }
        .onKeyPress(.space) { player.togglePlay(); return .handled }
        .keyboardShortcut("k", modifiers: .command)
    }
}
