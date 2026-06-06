import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) var library
    @Environment(PlayerService.self) var player
    @State private var selected: AlbumSummary?
    @State private var hoveredID: String?

    private let columns = [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: VGSpace.md)]

    var body: some View {
        if let album = selected {
            AlbumDetailView(summary: album, onBack: { selected = nil })
        } else {
            libraryGrid
        }
    }

    private var libraryGrid: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Text("Library")
                    .font(VGFont.title())
                    .foregroundStyle(Color.vgText)
                    .padding(.top, VGSpace.xl)
                    .padding(.horizontal, VGSpace.xl)

                if library.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 60)
                } else if library.albums.isEmpty {
                    emptyState
                } else {
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

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.sm) {
            ZStack(alignment: .bottomTrailing) {
                AlbumLetterArt(title: album.title, size: 160)

                if isHovered {
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
                PlatformPill(platform: album.platform)
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
