import SwiftUI

/// Scratch accumulator for scroll-wheel swipe detection. A plain reference type so
/// mutating it during every scroll event doesn't trigger a SwiftUI re-render — only
/// promoting a value into @State (once a gesture is confirmed horizontal) should do that.
private final class SwipeAccumulator {
    var x: CGFloat = 0
    var y: CGFloat = 0
}

enum SidebarItem: Hashable {
    case library
    case browse
    case downloaded
    case recentlyPlayed
    case playlistLiked
    case playlist(id: String)
    case settings
}

struct ContentView: View {
    @Environment(LibraryStore.self) var library
    @Environment(PlayerService.self) var player
    @Environment(AuthStore.self) var auth
    @Environment(FavoritesStore.self) var favorites
    @Environment(HiddenTracksStore.self) var hidden
    @State private var selection: SidebarItem = .library
    @State private var showAddURL = false
    @State private var showSearch = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var spaceKeyMonitor: Any?
    @State private var backSwipeMonitor: Any?
    @State private var backSwipeAccumX: CGFloat = 0
    @State private var backSwipeTracker = SwipeAccumulator()

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(selection: $selection)
                    .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 220)
            } detail: {
                ZStack {
                    Color.vgBg.ignoresSafeArea()
                    detailView

                    HStack {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.white.opacity(Double(backSwipeVisualProgress) * 0.7))
                            .scaleEffect(0.5 + backSwipeVisualProgress * 0.5)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .allowsHitTesting(false)
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
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
                .onKeyPress(.escape) { showAddURL = false; return .handled }
            }
        }
        .overlay {
            if showSearch { SearchOverlay(isShowing: $showSearch) }
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
        .onChange(of: auth.currentUser?.id) { _, userID in
            Task {
                if userID != nil { await favorites.load() }
                else { favorites.clear() }
            }
        }
        .onAppear {
            Task { await library.load() }
            Task { await favorites.load() }
            spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 49 else { return event }
                if let responder = NSApp.keyWindow?.firstResponder,
                   responder is NSText || responder is NSTextView { return event }
                player.togglePlay()
                return nil
            }
            // Two-finger trackpad swipe-back, like Library's browser nav, to
            // return to Library from flat sidebar sections (Favorites, Descargado, etc).
            backSwipeMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.hasPreciseScrollingDeltas, selection != .library else { return event }
                switch event.phase {
                case .began:
                    backSwipeTracker.x = 0
                    backSwipeTracker.y = 0
                    if backSwipeAccumX != 0 { backSwipeAccumX = 0 }
                case .changed:
                    backSwipeTracker.x += event.scrollingDeltaX
                    backSwipeTracker.y += event.scrollingDeltaY
                    // Only surface progress (and trigger a re-render) once the
                    // gesture is clearly horizontal — avoids re-rendering on every
                    // frame of ordinary vertical scrolling.
                    if abs(backSwipeTracker.x) > abs(backSwipeTracker.y) * 1.5 {
                        backSwipeAccumX = backSwipeTracker.x
                    } else if backSwipeAccumX != 0 {
                        backSwipeAccumX = 0
                    }
                case .ended, .cancelled:
                    if backSwipeTracker.x > 80 && backSwipeTracker.x > abs(backSwipeTracker.y) * 2 {
                        selection = .library
                    }
                    backSwipeAccumX = 0
                default: break
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = spaceKeyMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = backSwipeMonitor { NSEvent.removeMonitor(monitor) }
        }
        .onChange(of: library.pendingNavigation) { _, album in
            if album != nil { selection = .library }
        }
        .background {
            Group {
                Button("") { showSearch = true           }.keyboardShortcut("k", modifiers: .command)
                Button("") { selection = .library        }.keyboardShortcut("1", modifiers: .command)
                Button("") { selection = .browse         }.keyboardShortcut("2", modifiers: .command)
                Button("") { selection = .playlistLiked  }.keyboardShortcut("3", modifiers: .command)
                Button("") { showAddURL = true           }.keyboardShortcut("5", modifiers: .command)
                Button("") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                    }
                }.keyboardShortcut("b", modifiers: .command)
                Button("") { Task { await library.load() } }.keyboardShortcut("r", modifiers: .command)
                Button("") {
                    guard let track = player.currentTrack else { return }
                    hidden.toggle(track.id)
                    player.next()
                }.keyboardShortcut(.delete, modifiers: .command)
                Button("") {
                    guard let track = player.currentTrack, let album = player.currentAlbum else { return }
                    favorites.toggle(track, album: album)
                }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button("") { selection = .settings }.keyboardShortcut(",", modifiers: .command)
            }
            .hidden()
        }
    }

    private var backSwipeVisualProgress: CGFloat {
        guard selection != .library else { return 0 }
        return min(max(backSwipeAccumX, 0) / 120, 1)
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .library:       LibraryView()
        case .downloaded:    DownloadedView()
        case .browse:        BrowseView()
        case .recentlyPlayed: RecentlyPlayedView()
        case .playlistLiked: LikedMusicView()
        case .playlist(let id): PlaylistDetailView(playlistId: id)
        case .settings:      SettingsView()
        }
    }
}
