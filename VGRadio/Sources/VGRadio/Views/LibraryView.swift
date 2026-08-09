import SwiftUI

/// Scratch accumulator for scroll-wheel swipe detection. A plain reference type so
/// mutating it during every scroll event doesn't trigger a SwiftUI re-render — only
/// promoting a value into @State (once a gesture is confirmed horizontal) should do that.
private final class SwipeAccumulator {
    var x: CGFloat = 0
    var y: CGFloat = 0
}

private enum LibraryViewMode: String {
    case grid, list, compact
}

struct LibraryView: View {
    @Environment(LibraryStore.self) var library
    @Environment(PlayerService.self) var player
    // Browser-style navigation history: nil = grid, non-nil = album detail
    @State private var history: [AlbumSummary?] = [nil]
    @State private var historyIndex = 0
    @State private var swipeAccumX: CGFloat = 0
    @State private var swipeTracker = SwipeAccumulator()
    @State private var scrollMonitor: Any?
    @State private var hoveredID: String?
    @State private var searchText = ""
    @State private var searchFocused = false
    @State private var pendingDeleteAlbum: AlbumSummary?
    @State private var isDeletingAlbum = false
    @FocusState private var searchFieldFocused: Bool
    @AppStorage("vgradio.libraryViewMode") private var viewMode = LibraryViewMode.grid

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: VGSpace.md)]
    private let compactColumns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 2)]

    private var selected: AlbumSummary? { history[historyIndex] }

    private var filteredAlbums: [AlbumSummary] {
        guard !searchText.isEmpty else { return library.albums }
        return library.albums.filter {
            matchesSearchQuery($0.title, searchText) || matchesSearchQuery($0.platform, searchText)
        }
    }

    private func navigate(to album: AlbumSummary?) {
        guard history[historyIndex] != album else { return }
        history.removeSubrange((historyIndex + 1)...)
        history.append(album)
        historyIndex = history.count - 1
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        DispatchQueue.main.async { historyIndex -= 1 }
    }

    private func goForward() {
        guard historyIndex < history.count - 1 else { return }
        DispatchQueue.main.async { historyIndex += 1 }
    }

    private var backSwipeProgress: CGFloat {
        guard historyIndex > 0 else { return 0 }
        return min(max(swipeAccumX, 0) / 120, 1)
    }

    private var forwardSwipeProgress: CGFloat {
        guard historyIndex < history.count - 1 else { return 0 }
        return min(max(-swipeAccumX, 0) / 120, 1)
    }

    var body: some View {
        ZStack {
            Group {
                if let album = selected {
                    // Identity keyed on the album so navigating between two albums
                    // (or stepping back through history) rebuilds the detail view
                    // instead of SwiftUI reusing the previous album's state.
                    AlbumDetailView(summary: album, onBack: goBack)
                        .id(album.id)
                } else {
                    libraryGrid
                }
            }

            HStack {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.white.opacity(Double(backSwipeProgress) * 0.7))
                    .scaleEffect(0.5 + backSwipeProgress * 0.5)
                Spacer()
                Image(systemName: "chevron.right.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(Color.white.opacity(Double(forwardSwipeProgress) * 0.7))
                    .scaleEffect(0.5 + forwardSwipeProgress * 0.5)
            }
            .padding(.horizontal, 24)
            .allowsHitTesting(false)
        }
        .onAppear {
            if let album = library.pendingNavigation {
                navigate(to: album)
                library.pendingNavigation = nil
            }
        }
        .onChange(of: library.pendingNavigation) { _, album in
            if let album {
                navigate(to: album)
                library.pendingNavigation = nil
            }
        }
        .background {
            Group {
                Button("") { goBack() }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("") { goForward() }.keyboardShortcut(.rightArrow, modifiers: .command)
                if selected == nil {
                    Button("") { searchFieldFocused = true }.keyboardShortcut("f", modifiers: .command)
                }
            }
            .hidden()
        }
        .onAppear {
            // Two-finger trackpad swipe, like browser back/forward navigation.
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                guard event.hasPreciseScrollingDeltas else { return event }
                switch event.phase {
                case .began:
                    swipeTracker.x = 0
                    swipeTracker.y = 0
                    if swipeAccumX != 0 { swipeAccumX = 0 }
                case .changed:
                    swipeTracker.x += event.scrollingDeltaX
                    swipeTracker.y += event.scrollingDeltaY
                    // Only surface progress (and trigger a re-render) once the
                    // gesture is clearly horizontal — avoids re-rendering on every
                    // frame of ordinary vertical scrolling through the grid.
                    if abs(swipeTracker.x) > abs(swipeTracker.y) * 1.5 {
                        swipeAccumX = swipeTracker.x
                    } else if swipeAccumX != 0 {
                        swipeAccumX = 0
                    }
                case .ended, .cancelled:
                    if abs(swipeTracker.x) > 80 && abs(swipeTracker.x) > abs(swipeTracker.y) * 2 {
                        if swipeTracker.x > 0 { goBack() } else { goForward() }
                    }
                    swipeAccumX = 0
                default: break
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = scrollMonitor { NSEvent.removeMonitor(monitor) }
        }
        .confirmationDialog(
            "¿Eliminar \"\(pendingDeleteAlbum?.title ?? "")\" de tu library?",
            isPresented: Binding(
                get: { pendingDeleteAlbum != nil },
                set: { if !$0 { pendingDeleteAlbum = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                guard let album = pendingDeleteAlbum else { return }
                isDeletingAlbum = true
                Task {
                    try? await library.deleteAlbum(album.id)
                    isDeletingAlbum = false
                    pendingDeleteAlbum = nil
                }
            }
            Button("Cancelar", role: .cancel) { pendingDeleteAlbum = nil }
        } message: {
            Text("Esto borra el álbum, sus tracks y descargas locales. No se puede deshacer.")
        }
    }

    private var libraryGrid: some View {
        ScrollView {
            VStack(alignment: .leading) {
                HStack(alignment: .lastTextBaseline, spacing: VGSpace.sm) {
                    Text("Library")
                        .font(VGFont.title())
                        .foregroundStyle(Color.vgText)

                    if !library.albums.isEmpty {
                        Text("\(library.albums.count) albums")
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextMuted)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("FILTER")
                            .font(VGFont.label(10))
                            .tracking(1.2)
                            .foregroundStyle(Color.vgTextMuted)
                        HStack(spacing: VGSpace.xs) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Color.vgTextMuted)
                            TextField("Filter albums…", text: $searchText)
                                .textFieldStyle(.plain)
                                .font(VGFont.body())
                                .focused($searchFieldFocused)
                                .onKeyPress(.escape) {
                                    searchText = ""
                                    searchFieldFocused = false
                                    return .handled
                                }
                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(Color.vgTextMuted)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, VGSpace.sm)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .frame(width: 220)

                    HStack(spacing: 2) {
                        Button { viewMode = .grid } label: {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(viewMode == .grid ? Color.vgAccent : Color.vgTextMuted)
                                .frame(width: 26, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Grid view")

                        Button { viewMode = .compact } label: {
                            Image(systemName: "square.grid.3x3")
                                .foregroundStyle(viewMode == .compact ? Color.vgAccent : Color.vgTextMuted)
                                .frame(width: 26, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Compact view")

                        Button { viewMode = .list } label: {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(viewMode == .list ? Color.vgAccent : Color.vgTextMuted)
                                .frame(width: 26, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("List view")
                    }
                    .padding(2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .padding(.top, VGSpace.sm)
                .padding(.horizontal, VGSpace.xl)

                if library.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                } else if library.albums.isEmpty {
                    emptyState
                } else {
                    if !library.albums.isEmpty {
                        if !searchText.isEmpty && filteredAlbums.isEmpty {
                            Text("No results for \"\(searchText)\"")
                                .font(VGFont.body())
                                .foregroundStyle(Color.vgTextMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        } else if viewMode == .list {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredAlbums) { album in
                                    AlbumListRow(album: album, isHovered: hoveredID == album.id)
                                        .onHover { hoveredID = $0 ? album.id : nil }
                                        .onTapGesture { navigate(to: album) }
                                        .contextMenu {
                                            Button(role: .destructive) { pendingDeleteAlbum = album } label: {
                                                Label("Eliminar de la library", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, VGSpace.xl)
                            .padding(.top, VGSpace.md)
                        } else if viewMode == .compact {
                            LazyVGrid(columns: compactColumns, spacing: 2) {
                                ForEach(filteredAlbums) { album in
                                    CompactAlbumCard(album: album)
                                        .onTapGesture { navigate(to: album) }
                                        .contextMenu {
                                            Button(role: .destructive) { pendingDeleteAlbum = album } label: {
                                                Label("Eliminar de la library", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, VGSpace.xl)
                            .padding(.top, VGSpace.md)
                        } else {
                            LazyVGrid(columns: columns, spacing: VGSpace.md) {
                                ForEach(filteredAlbums) { album in
                                    AlbumCard(album: album, isHovered: hoveredID == album.id)
                                        .onHover { hoveredID = $0 ? album.id : nil }
                                        .onTapGesture { navigate(to: album) }
                                        .contextMenu {
                                            Button(role: .destructive) { pendingDeleteAlbum = album } label: {
                                                Label("Eliminar de la library", systemImage: "trash")
                                            }
                                        }
                                }
                            }
                            .padding(.horizontal, VGSpace.xl)
                            .padding(.vertical, VGSpace.lg)
                        }
                    }
                }
            }
        }
        .background(Color.vgBg)
    }

    private var emptyState: some View {
        VStack(spacing: VGSpace.md) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(Color.vgTextMuted)
            Text("No albums yet")
                .font(VGFont.heading())
                .foregroundStyle(Color.vgTextSec)
            Text("Use Add URL to import an album from khinsider.")
                .font(VGFont.body())
                .foregroundStyle(Color.vgTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Album Card

private struct AlbumCard: View {
    let album: AlbumSummary
    let isHovered: Bool
    @Environment(OfflineStore.self) var offline

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.sm) {
            ZStack(alignment: .bottomTrailing) {
                AlbumCoverView(
                    covers: album.covers,
                    title: album.title,
                    size: 160,
                    initialIndex: CoverPrefsStore.shared.index(for: album.id),
                    enableHoverControls: false
                )

                if offline.isAlbumDownloaded(albumID: album.id, totalTracks: album.trackCount) {
                    Image(systemName: "checkmark.icloud.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(Color.green)
                        .clipShape(Circle())
                        .padding(6)
                }

                if isHovered && album.covers.isEmpty {
                    Circle()
                        .fill(Color.vgAccent)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "play.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        )
                        .padding(VGSpace.sm)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.2), value: isHovered)

            Text(album.title)
                .font(VGFont.body())
                .fontWeight(.medium)
                .foregroundStyle(Color.vgText)
                .lineLimit(2)

            HStack(spacing: 4) {
                // Show first platform only in compact card
                let firstPlatform = album.platform.split(separator: ",").first.map(String.init) ?? album.platform
                PlatformPill(platform: firstPlatform.trimmingCharacters(in: .whitespaces))
                Text("·").foregroundStyle(Color.vgTextMuted)
                Text(String(album.year)).font(VGFont.caption()).foregroundStyle(Color.vgTextMuted)
                if !album.totalDurationFormatted.isEmpty {
                    Text("·").foregroundStyle(Color.vgTextMuted)
                    Text(album.totalDurationFormatted).font(VGFont.caption()).foregroundStyle(Color.vgTextMuted)
                }
            }
        }
        .padding(VGSpace.sm)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Compact Album Card (cover-only grid, no epigraph, near-zero gap)

private struct CompactAlbumCard: View {
    let album: AlbumSummary
    @Environment(OfflineStore.self) var offline
    @Environment(FavoritesStore.self) var favorites
    @State private var showTooltip = false
    @State private var hoverTask: Task<Void, Never>?

    private var isDownloaded: Bool { offline.isAlbumDownloaded(albumID: album.id, totalTracks: album.trackCount) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AlbumCoverView(
                covers: album.covers,
                title: album.title,
                size: 160,
                initialIndex: CoverPrefsStore.shared.index(for: album.id),
                enableHoverControls: false
            )

            if isDownloaded {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.green)
                    .clipShape(Circle())
                    .padding(6)
            }
        }
        .contentShape(Rectangle())
        .onHover { inside in
            hoverTask?.cancel()
            if inside {
                // Near-instant custom tooltip — AppKit's native .help() still
                // has a perceptible delay even at its lowest setting, and can't
                // show rich, multi-line content (title + platform + downloaded state).
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    if !Task.isCancelled { showTooltip = true }
                }
            } else {
                showTooltip = false
            }
        }
        .overlay(alignment: .top) {
            if showTooltip {
                CompactAlbumTooltip(album: album, isFavorited: favorites.isAlbumFavorited(album.id), isDownloaded: isDownloaded)
                    .offset(y: -8)
                    .zIndex(10)
                    .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Compact card tooltip (custom, appears near-instantly on hover)

private struct CompactAlbumTooltip: View {
    let album: AlbumSummary
    let isFavorited: Bool
    let isDownloaded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(album.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
                if isFavorited {
                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Color.vgStar)
                }
                if isDownloaded {
                    Image(systemName: "checkmark.icloud.fill").font(.system(size: 9)).foregroundStyle(Color.green)
                }
            }
            let firstPlatform = album.platform.split(separator: ",").first.map(String.init) ?? album.platform
            Text("\(firstPlatform.trimmingCharacters(in: .whitespaces))  ·  \(String(album.year))\(album.totalDurationFormatted.isEmpty ? "" : "  ·  \(album.totalDurationFormatted)")")
                .font(.system(size: 10))
                .foregroundStyle(Color.vgTextSec)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.1)))
        .fixedSize()
    }
}

// MARK: - Album List Row

private struct AlbumListRow: View {
    let album: AlbumSummary
    let isHovered: Bool
    @Environment(OfflineStore.self) var offline

    var body: some View {
        HStack(spacing: VGSpace.md) {
            AlbumCoverView(
                covers: album.covers,
                title: album.title,
                size: 48,
                initialIndex: CoverPrefsStore.shared.index(for: album.id),
                enableHoverControls: false
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(album.title)
                        .font(VGFont.body())
                        .fontWeight(.medium)
                        .foregroundStyle(Color.vgText)
                        .lineLimit(1)
                    if offline.isAlbumDownloaded(albumID: album.id, totalTracks: album.trackCount) {
                        Image(systemName: "checkmark.icloud.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.green)
                    }
                }
                HStack(spacing: 4) {
                    let firstPlatform = album.platform.split(separator: ",").first.map(String.init) ?? album.platform
                    PlatformPill(platform: firstPlatform.trimmingCharacters(in: .whitespaces))
                    Text("·").foregroundStyle(Color.vgTextMuted)
                    Text(String(album.year)).font(VGFont.caption()).foregroundStyle(Color.vgTextMuted)
                }
            }

            Spacer()

            Text(album.totalDurationFormatted)
                .font(VGFont.mono(12))
                .foregroundStyle(Color.vgTextSec)
                .frame(width: 70, alignment: .trailing)

            Text("\(album.trackCount) tracks")
                .font(VGFont.caption())
                .foregroundStyle(Color.vgTextMuted)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, VGSpace.sm)
        .padding(.vertical, 4)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

// MARK: - Platform pill

struct PlatformPill: View {
    let platform: String

    private var color: Color {
        switch platform.lowercased() {
        case "3ds": return .blue
        case "snes", "super nintendo": return Color(hex: "#7B3FBE")
        case "gc", "gamecube": return Color(hex: "#7B4B9E")
        case "n64": return .orange
        case "gba": return Color(hex: "#B84040")
        case "nes": return .gray
        case "switch": return Color(hex: "#E60012")
        default: return Color(hex: "#4A6080")
        }
    }

    var body: some View {
        Text(platform)
            .font(VGFont.caption(10))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.8))
            .clipShape(Capsule())
    }
}
