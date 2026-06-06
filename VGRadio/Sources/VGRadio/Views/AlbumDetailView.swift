import SwiftUI

struct AlbumDetailView: View {
    let summary: AlbumSummary
    let onBack: () -> Void

    @Environment(PlayerService.self) var player
    @Environment(FavoritesStore.self) var favorites
    @Environment(HiddenTracksStore.self) var hidden
    @State private var album: Album?
    @State private var isLoading = true
    @State private var hoveredTrackID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button { onBack() } label: {
                    Label("Library", systemImage: "chevron.left")
                        .font(VGFont.caption(12))
                        .foregroundStyle(Color.vgTextSec)
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
                .padding(.horizontal, 32)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if let album {
                    albumContent(album)
                }
            }
        }
        .background(Color.vgBg)
        .task { await load() }
    }

    @ViewBuilder
    private func albumContent(_ album: Album) -> some View {
        // Hero header
        HStack(alignment: .top, spacing: 24) {
            AlbumCoverView(
                covers: album.covers,
                title: album.title,
                size: VGLayout.albumCoverDetail,
                initialIndex: CoverPrefsStore.shared.index(for: summary.id),
                onIndexChange: {
                    player.currentCoverIndex = $0
                    CoverPrefsStore.shared.set($0, for: summary.id)
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(album.albumType.isEmpty ? "SOUNDTRACK" : album.albumType.uppercased())
                    .font(VGFont.label(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.vgTextMuted)

                Text(album.title)
                    .font(VGFont.display(30))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Alt titles (Japanese, etc.)
                let altLines = album.altTitle.split(separator: "\n").map(String.init)
                if !altLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(altLines, id: \.self) { line in
                            Text(line)
                                .font(VGFont.body(12))
                                .foregroundStyle(Color.vgTextSec)
                        }
                    }
                }

                // Platform pills + year
                HStack(spacing: 6) {
                    let platforms = album.platform.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    ForEach(platforms.prefix(4), id: \.self) { p in
                        PlatformPill(platform: p)
                    }
                    if album.year > 0 {
                        Text("·").foregroundStyle(Color.vgTextMuted)
                        Text(String(album.year))
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextSec)
                    }
                }

                // Publisher · Developer · Catalog
                metaRow(album)

                Spacer(minLength: 12)

                // Actions
                HStack(spacing: 10) {
                    Button {
                        if let first = album.tracks.first(where: { !(hidden.isHidden($0.id)) }) ?? album.tracks.first {
                            player.play(track: first, in: summary, queue: album.tracks, covers: album.covers)
                            player.currentCoverIndex = CoverPrefsStore.shared.index(for: summary.id)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12))
                            Text("Play").font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.vgBg)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color.vgAccent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    CircleIconButton(icon: "arrow.down.circle")

                    // Star: adds/removes all tracks for this album
                    let allFav = favorites.isAlbumFavorited(summary.id)
                    Button {
                        if allFav {
                            favorites.removeAll(albumID: summary.id)
                        } else {
                            favorites.addAll(album.tracks, album: summary)
                        }
                    } label: {
                        Image(systemName: allFav ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(allFav ? Color.vgStar : Color.vgTextSec)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    Text("\(album.tracks.count) tracks")
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgTextMuted)
                        .padding(.leading, 4)
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 24)
        .padding(.bottom, 32)

        // Tracklist
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                Text("#").frame(width: 40, alignment: .center)
                Text("TITLE").frame(maxWidth: .infinity, alignment: .leading)
                Text("DUR").frame(width: 60, alignment: .trailing)
                Text("👍").frame(width: 40, alignment: .center)
                Text("👁").frame(width: 40, alignment: .center)
            }
            .font(VGFont.label(10))
            .tracking(1.0)
            .foregroundStyle(Color.vgTextMuted)
            .frame(height: 32)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.02))

            ForEach(Array(album.tracks.enumerated()), id: \.element.id) { idx, track in
                DetailTrackRow(
                    track: track,
                    album: summary,
                    isAltRow: idx % 2 == 1,
                    isHovered: hoveredTrackID == track.id,
                    isPlaying: player.currentTrack?.id == track.id
                )
                .onHover { hoveredTrackID = $0 ? track.id : nil }
                .onTapGesture(count: 2) {
                    player.play(track: track, in: summary, queue: album.tracks, covers: album.covers)
                    player.currentCoverIndex = CoverPrefsStore.shared.index(for: summary.id)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.vgBorder60))
        .background(Color.vgSurface.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 10)))
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private func metaRow(_ album: Album) -> some View {
        let items: [(String, String)] = [
            ("person.fill",    album.developer),
            ("building.fill",  album.publisher),
            ("barcode",        album.catalogNumber),
        ].filter { !$0.1.isEmpty }

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.0) { icon, value in
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.vgTextMuted)
                            .frame(width: 14)
                        Text(value)
                            .font(VGFont.caption(12))
                            .foregroundStyle(Color.vgTextSec)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        album = try? await APIClient.shared.album(summary.id)
        isLoading = false
    }
}

// MARK: - Cover image (real or letter fallback)

struct AlbumCoverView: View {
    let covers: [Cover]
    let title: String
    let size: CGFloat
    var initialIndex: Int = 0
    var enableHoverControls = true
    var onIndexChange: ((Int) -> Void)? = nil

    @State private var coverIndex = 0
    @State private var isHovered = false

    static func resolveURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: APIClient.shared.baseURL + path)
    }

    var body: some View {
        let safeIndex = covers.isEmpty ? -1 : min(coverIndex, covers.count - 1)
        ZStack {
            Group {
                if safeIndex >= 0, let url = Self.resolveURL(covers[safeIndex].url) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                        default:
                            AlbumLetterArt(title: title, size: size)
                        }
                    }
                } else {
                    AlbumLetterArt(title: title, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if enableHoverControls && isHovered && covers.count > 1 {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: size, height: size)

                HStack {
                    Button {
                        let newIdx = max(0, coverIndex - 1)
                        withAnimation(.easeInOut(duration: 0.15)) { coverIndex = newIdx }
                        onIndexChange?(newIdx)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(coverIndex > 0 ? 1 : 0.3)

                    Spacer()

                    Button {
                        let newIdx = min(covers.count - 1, coverIndex + 1)
                        withAnimation(.easeInOut(duration: 0.15)) { coverIndex = newIdx }
                        onIndexChange?(newIdx)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(coverIndex < covers.count - 1 ? 1 : 0.3)
                }
                .padding(.horizontal, 8)
                .frame(width: size)

                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<covers.count, id: \.self) { i in
                            Circle()
                                .fill(i == coverIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.vgAccent.opacity(0.15), radius: 20, y: 8)
        .onHover { isHovered = $0 }
        .onAppear { coverIndex = min(initialIndex, max(0, covers.count - 1)) }
    }
}

// MARK: - Track row

private struct DetailTrackRow: View {
    let track: Track
    let album: AlbumSummary
    let isAltRow: Bool
    let isHovered: Bool
    let isPlaying: Bool
    @Environment(FavoritesStore.self) var favorites
    @Environment(HiddenTracksStore.self) var hidden

    private var isHidden: Bool { hidden.isHidden(track.id) }
    private var isFav: Bool { favorites.isFavorite(track.id) }

    var body: some View {
        ZStack(alignment: .leading) {
            if isPlaying {
                Color.vgAccentBg
                Color.vgAccent.frame(width: 2)
            } else if isHovered && !isHidden {
                Color.white.opacity(0.04)
            } else if isAltRow {
                Color.white.opacity(0.015)
            }

            HStack(spacing: 0) {
                // Index / play / hidden indicator
                Group {
                    if isHidden {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(Color.vgTextMuted).font(.system(size: 11))
                    } else if isPlaying {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.vgAccent).font(.system(size: 12))
                    } else if isHovered {
                        Image(systemName: "play.fill")
                            .foregroundStyle(Color.vgText).font(.system(size: 11))
                    } else {
                        Text(String(format: "%02d", track.index))
                            .font(VGFont.mono(12)).foregroundStyle(Color.vgTextMuted)
                    }
                }
                .frame(width: 40, alignment: .center)

                Text(track.name)
                    .font(VGFont.body(13))
                    .foregroundStyle(isHidden ? Color.vgTextMuted : isPlaying ? Color.vgAccent : Color.vgText)
                    .strikethrough(isHidden, color: Color.vgTextMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(track.durationFormatted)
                    .font(VGFont.mono(12))
                    .foregroundStyle(isHidden ? Color.vgTextMuted.opacity(0.5) : Color.vgTextSec)
                    .frame(width: 60, alignment: .trailing)
                    .monospacedDigit()

                // Thumbs up (favorite) — shown on hover or when already favorited
                Button { favorites.toggle(track, album: album) } label: {
                    Group {
                        if isHovered || isFav {
                            Image(systemName: isFav ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 12))
                                .foregroundStyle(isFav ? Color.vgStar : Color.vgTextSec)
                                .scaleEffect(isFav ? 1.1 : 1)
                        } else {
                            Color.clear
                        }
                    }
                    .animation(.spring(response: 0.2), value: isFav)
                }
                .buttonStyle(.plain)
                .frame(width: 40, alignment: .center)

                // Hide toggle (swipe-down button) — always visible as subtle indicator when hidden, shown on hover
                Button { hidden.toggle(track.id) } label: {
                    Image(systemName: isHidden ? "eye.slash.fill" : "arrow.down.to.line")
                        .font(.system(size: 12))
                        .foregroundStyle(isHidden ? Color.vgAccent.opacity(0.7) : isHovered ? Color.vgTextSec : Color.clear)
                }
                .buttonStyle(.plain)
                .frame(width: 40, alignment: .center)
                .help(isHidden ? "Mostrar en reproducción automática" : "Ocultar de reproducción automática")
            }
            .padding(.horizontal, 12)
            .opacity(isHidden ? 0.45 : 1)
        }
        .frame(height: VGLayout.trackRowHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { v in
                    if v.translation.height > 20 && abs(v.translation.width) < 40 {
                        hidden.toggle(track.id)
                    }
                }
        )
    }
}

// MARK: - Helpers

private struct CircleIconButton: View {
    let icon: String
    var body: some View {
        Button {} label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Color.vgTextSec)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.05))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
