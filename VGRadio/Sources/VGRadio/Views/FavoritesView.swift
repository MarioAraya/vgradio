import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesStore.self) var favorites
    @Environment(PlayerService.self) var player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VGSpace.lg) {
                // Header
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Favorites")
                            .font(VGFont.title())
                            .foregroundStyle(Color.vgText)
                        Text(subtitle)
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextSec)
                    }
                    Spacer()
                    if !favorites.favorites.isEmpty {
                        Button {
                            shuffleAll()
                        } label: {
                            Label("Shuffle all", systemImage: "shuffle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.vgAccent)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.vgAccent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Reproducir favoritos en orden aleatorio")
                    }
                }
                .padding(.top, VGSpace.xl)
                .padding(.horizontal, VGSpace.xl)

                if favorites.grouped.isEmpty {
                    emptyState
                } else {
                    ForEach(favorites.grouped, id: \.albumId) { group in
                        FavoriteGroupView(group: group)
                    }
                    .padding(.horizontal, VGSpace.xl)
                }
            }
            .padding(.bottom, VGSpace.xl)
        }
        .background(Color.vgBg)
    }

    private func shuffleAll() {
        var allTracks = favorites.favorites.enumerated().map { $0.element.asTrack(index: $0.offset + 1) }
        allTracks.shuffle()
        guard let first = allTracks.first else { return }
        let album = AlbumSummary(id: "favorites", title: "Favorites",
                                 platform: "", year: 0, albumType: "",
                                 trackCount: allTracks.count, coverUrls: [])
        player.play(track: first, in: album, queue: allTracks)
    }

    private var subtitle: String {
        let total = favorites.favorites.count
        let albums = favorites.grouped.count
        if total == 0 { return "No starred tracks yet" }
        return "\(total) starred track\(total == 1 ? "" : "s") across \(albums) album\(albums == 1 ? "" : "s")"
    }

    private var emptyState: some View {
        VStack(spacing: VGSpace.md) {
            Image(systemName: "star")
                .font(.system(size: 40))
                .foregroundStyle(Color.vgTextMuted)
            Text("No favorites yet")
                .font(VGFont.heading())
                .foregroundStyle(Color.vgTextSec)
            Text("Star tracks while listening to save them here.")
                .font(VGFont.body())
                .foregroundStyle(Color.vgTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Group

private struct FavoriteGroupView: View {
    let group: (albumId: String, albumTitle: String, platform: String, year: Int, coverUrls: [String], tracks: [FavoriteTrack])

    private var albumSummary: AlbumSummary {
        AlbumSummary(id: group.albumId, title: group.albumTitle,
                     platform: group.platform, year: group.year,
                     albumType: "", trackCount: group.tracks.count, coverUrls: group.coverUrls)
    }

    private var queueTracks: [Track] {
        group.tracks.enumerated().map { $0.element.asTrack(index: $0.offset + 1) }
    }

    private var covers: [Cover] {
        group.coverUrls.map { Cover(url: $0, width: 0, height: 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Album header
            HStack(spacing: VGSpace.md) {
                AlbumCoverView(covers: covers, title: group.albumTitle, size: 48,
                               enableHoverControls: false)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.albumTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.vgText)
                    Text("\(group.platform)  ·  \(group.year)")
                        .font(VGFont.mono(11))
                        .foregroundStyle(Color.vgTextSec)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(.bottom, VGSpace.sm)

            // Track table
            VStack(spacing: 0) {
                // Header row
                HStack {
                    Text("#").frame(width: 32, alignment: .trailing)
                    Text("TITLE").frame(maxWidth: .infinity, alignment: .leading)
                    Text("DUR").frame(width: 50, alignment: .trailing)
                    Text("★").frame(width: 28, alignment: .center)
                }
                .font(VGFont.caption(11))
                .foregroundStyle(Color.vgTextMuted)
                .padding(.horizontal, VGSpace.md)
                .padding(.vertical, VGSpace.sm)

                Divider().overlay(Color.vgSeparator)

                ForEach(Array(group.tracks.enumerated()), id: \.element.id) { i, track in
                    FavoriteTrackRow(track: track, rowIndex: i + 1,
                                     album: albumSummary, queue: queueTracks)
                }
            }
            .background(Color.vgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Track row

private struct FavoriteTrackRow: View {
    let track: FavoriteTrack
    let rowIndex: Int
    let album: AlbumSummary
    let queue: [Track]
    @Environment(FavoritesStore.self) var favorites
    @Environment(PlayerService.self) var player
    @State private var isHovered = false

    private var isPlaying: Bool { player.currentTrack?.id == track.id && player.isPlaying }

    var body: some View {
        HStack {
            Group {
                if isPlaying {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.vgAccent)
                } else {
                    Text(String(format: "%02d", rowIndex))
                        .font(VGFont.mono())
                        .foregroundStyle(Color.vgTextMuted)
                }
            }
            .frame(width: 32, alignment: .trailing)

            Text(track.name)
                .font(VGFont.body())
                .foregroundStyle(isPlaying ? Color.vgAccent : Color.vgText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.durationFormatted)
                .font(VGFont.mono())
                .foregroundStyle(Color.vgTextSec)
                .frame(width: 50, alignment: .trailing)

            Image(systemName: "hand.thumbsup.fill")
                .foregroundStyle(Color.vgStar)
                .frame(width: 28, alignment: .center)
                .onTapGesture {
                    favorites.toggle(track.asTrack(index: rowIndex), album: album)
                }
                .help("Quitar de favoritos")
        }
        .padding(.horizontal, VGSpace.md)
        .padding(.vertical, 10)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) {
            let t = track.asTrack(index: rowIndex)
            player.play(track: t, in: album, queue: queue)
        }
        .contentShape(Rectangle())

        Divider().overlay(Color.vgSeparator).padding(.horizontal, VGSpace.md)
    }
}

private extension FavoriteTrack {
    func asTrack(index: Int) -> Track {
        Track(id: id, index: index, name: name, durationSec: durationSec,
              sizeBytes: 0, streamUrl: "/tracks/\(id)/stream",
              downloadUrl: "/tracks/\(id)/download", downloaded: true)
    }
}
