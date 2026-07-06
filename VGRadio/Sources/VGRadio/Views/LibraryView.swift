import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) var library
    @Environment(WishlistStore.self) var wishlist
    @Environment(PlayerService.self) var player
    // Browser-style navigation history: nil = grid, non-nil = album detail
    @State private var history: [AlbumSummary?] = [nil]
    @State private var historyIndex = 0
    @State private var swipeAccumX: CGFloat = 0
    @State private var swipeAccumY: CGFloat = 0
    @State private var scrollMonitor: Any?
    @State private var hoveredID: String?
    @State private var importingURL: String?
    @State private var importError: String?
    @State private var searchText = ""
    @State private var searchFocused = false
    @State private var pendingDeleteAlbum: AlbumSummary?
    @State private var isDeletingAlbum = false
    @FocusState private var searchFieldFocused: Bool
    @AppStorage("vgradio.libraryListView") private var isListView = false

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: VGSpace.md)]

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
                    AlbumDetailView(summary: album, onBack: goBack)
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
                    swipeAccumX = 0
                    swipeAccumY = 0
                case .changed:
                    swipeAccumX += event.scrollingDeltaX
                    swipeAccumY += event.scrollingDeltaY
                case .ended, .cancelled:
                    if abs(swipeAccumX) > 80 && abs(swipeAccumX) > abs(swipeAccumY) * 2 {
                        if swipeAccumX > 0 { goBack() } else { goForward() }
                    }
                    swipeAccumX = 0
                    swipeAccumY = 0
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
                HStack(spacing: VGSpace.sm) {
                    Text("Library")
                        .font(VGFont.title())
                        .foregroundStyle(Color.vgText)

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
                        Button { isListView = false } label: {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(isListView ? Color.vgTextMuted : Color.vgAccent)
                                .frame(width: 26, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("Grid view")

                        Button { isListView = true } label: {
                            Image(systemName: "list.bullet")
                                .foregroundStyle(isListView ? Color.vgAccent : Color.vgTextMuted)
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
                } else if library.albums.isEmpty && wishlist.items.isEmpty {
                    emptyState
                } else {
                    if !library.albums.isEmpty {
                        if !searchText.isEmpty && filteredAlbums.isEmpty {
                            Text("No results for \"\(searchText)\"")
                                .font(VGFont.body())
                                .foregroundStyle(Color.vgTextMuted)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        } else if isListView {
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

                    if !wishlist.items.isEmpty && searchText.isEmpty {
                        wishlistSection
                    }
                }
            }
        }
        .background(Color.vgBg)
    }

    private var wishlistSection: some View {
        VStack(alignment: .leading, spacing: VGSpace.md) {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.vgTextMuted)
                Text("Not downloaded yet")
                    .font(VGFont.caption(12))
                    .foregroundStyle(Color.vgTextMuted)
            }
            .padding(.horizontal, VGSpace.xl)
            .padding(.top, library.albums.isEmpty ? VGSpace.lg : 0)

            if let err = importError {
                Text(err)
                    .font(VGFont.caption(11))
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(.horizontal, VGSpace.xl)
            }

            LazyVGrid(columns: columns, spacing: VGSpace.md) {
                ForEach(wishlist.items) { item in
                    WishlistCard(
                        item: item,
                        isImporting: importingURL == item.url,
                        onImport: { importItem(item) },
                        onRemove: { wishlist.remove(url: item.url) }
                    )
                }
            }
            .padding(.horizontal, VGSpace.xl)
            .padding(.bottom, VGSpace.lg)
        }
    }

    private func importItem(_ item: WishlistItem) {
        guard importingURL == nil else { return }
        importingURL = item.url
        importError = nil
        Task {
            do {
                try await library.importAlbum(url: item.url)
                wishlist.remove(url: item.url)
            } catch {
                importError = error.localizedDescription
            }
            importingURL = nil
        }
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

// MARK: - Album List Row

private struct AlbumListRow: View {
    let album: AlbumSummary
    let isHovered: Bool

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
                Text(album.title)
                    .font(VGFont.body())
                    .fontWeight(.medium)
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
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

// MARK: - Wishlist card

private struct WishlistCard: View {
    let item: WishlistItem
    let isImporting: Bool
    let onImport: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.03))
                    .frame(width: 160, height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(Color.white.opacity(0.15))
                    )

                if isImporting {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                } else if isHovered {
                    VStack(spacing: 6) {
                        Button(action: onImport) {
                            Label("Import", systemImage: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.vgBg)
                                .padding(.horizontal, 12)
                                .frame(height: 28)
                                .background(Color.vgAccent)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)

                        Button(action: onRemove) {
                            Text("Remove")
                                .font(VGFont.caption(11))
                                .foregroundStyle(Color.vgTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.white.opacity(0.2))
                }
            }
            .frame(width: 160, height: 160)
            .animation(.easeOut(duration: 0.15), value: isHovered)

            Text(item.displayTitle)
                .font(VGFont.body())
                .fontWeight(.medium)
                .foregroundStyle(Color.vgTextSec)
                .lineLimit(2)

            Text("Not downloaded")
                .font(VGFont.caption(10))
                .foregroundStyle(Color.vgTextMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())
        }
        .padding(VGSpace.sm)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onHover { isHovered = $0 }
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
