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
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var spaceKeyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: $selection, showAddURL: $showAddURL)
                    .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 180)
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
                .ignoresSafeArea(.all, edges: .top)
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar(.hidden, for: .windowToolbar)

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
        .overlay(alignment: .bottomTrailing) {
            if player.showQueue {
                QueuePanel()
                    .padding(.bottom, VGLayout.playerBarHeight + 8)
                    .padding(.trailing, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: player.showQueue)
        .onAppear {
            Task { await library.load() }
            spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 49 else { return event } // space
                if let responder = NSApp.keyWindow?.firstResponder,
                   responder is NSText || responder is NSTextView {
                    return event
                }
                player.togglePlay()
                return nil
            }
        }
        .onDisappear {
            if let monitor = spaceKeyMonitor { NSEvent.removeMonitor(monitor) }
        }
        .onChange(of: library.pendingNavigation) { _, album in
            if album != nil { selection = .library }
        }
        .keyboardShortcut("k", modifiers: .command)
        .background {
            Group {
                Button("") { selection = .library   }.keyboardShortcut("1", modifiers: .command)
                Button("") { selection = .browse    }.keyboardShortcut("2", modifiers: .command)
                Button("") { selection = .favorites }.keyboardShortcut("3", modifiers: .command)
                Button("") { showAddURL = true      }.keyboardShortcut("4", modifiers: .command)
                Button("") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                }.keyboardShortcut("b", modifiers: .command)
            }
            .hidden()
        }
    }
}
