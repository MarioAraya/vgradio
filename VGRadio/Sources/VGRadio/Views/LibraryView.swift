import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) var library
    @Environment(WishlistStore.self) var wishlist
    @Environment(PlayerService.self) var player
    @State private var selected: AlbumSummary?
    @State private var hoveredID: String?
    @State private var importingURL: String?
    @State private var importError: String?

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: VGSpace.md)]

    var body: some View {
        Group {
            if let album = selected {
                AlbumDetailView(summary: album, onBack: { selected = nil })
            } else {
                libraryGrid
            }
        }
        .onChange(of: library.pendingNavigation) { _, album in
            if let album {
                selected = album
                library.pendingNavigation = nil
            }
        }
    }

    private var libraryGrid: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Library")
                    .font(VGFont.title())
                    .foregroundStyle(Color.vgText)
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
                        LazyVGrid(columns: columns, spacing: VGSpace.md) {
                            ForEach(library.albums) { album in
                                AlbumCard(album: album, isHovered: hoveredID == album.id)
                                    .onHover { hoveredID = $0 ? album.id : nil }
                                    .onTapGesture { selected = album }
                            }
                        }
                        .padding(.horizontal, VGSpace.xl)
                        .padding(.vertical, VGSpace.lg)
                    }

                    if !wishlist.items.isEmpty {
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
        Task {
            do {
                let job = try await library.addAlbum(url: item.url)
                _ = try await library.pollJob(job.jobId)
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
            }
        }
        .padding(VGSpace.sm)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.15), value: isHovered)
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
