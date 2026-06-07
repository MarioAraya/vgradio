import SwiftUI

struct FavoritesView: View {
    @Environment(FavoritesStore.self) var favorites
    @Environment(PlayerService.self) var player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VGSpace.lg) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Favorites")
                        .font(VGFont.title())
                        .foregroundStyle(Color.vgText)
                    Text(subtitle)
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgTextSec)
                }
                .padding(.top, VGSpace.xl)
                .padding(.horizontal, VGSpace.xl)

                if favorites.grouped.isEmpty {
                    emptyState
                } else {
                    ForEach(favorites.grouped, id: \.albumTitle) { group in
                        FavoriteGroupView(group: group)
                    }
                    .padding(.horizontal, VGSpace.xl)
                }
            }
            .padding(.bottom, VGSpace.xl)
        }
        .background(Color.vgBg)
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
    let group: (albumTitle: String, platform: String, year: Int, tracks: [FavoriteTrack])

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Album header
            HStack(spacing: VGSpace.md) {
                AlbumLetterArt(title: group.albumTitle, size: 48)
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

                ForEach(group.tracks) { track in
                    FavoriteTrackRow(track: track)
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
    @Environment(FavoritesStore.self) var favorites
    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(String(format: "%02d", track.index ?? 0))
                .font(VGFont.mono())
                .foregroundStyle(Color.vgTextMuted)
                .frame(width: 32, alignment: .trailing)

            Text(track.name)
                .font(VGFont.body())
                .foregroundStyle(Color.vgText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.durationFormatted)
                .font(VGFont.mono())
                .foregroundStyle(Color.vgTextSec)
                .frame(width: 50, alignment: .trailing)

            // Always-filled star (these are favorites)
            Image(systemName: "star.fill")
                .foregroundStyle(Color.vgStar)
                .frame(width: 28, alignment: .center)
                .onTapGesture {
                    // Remove from favorites by creating a dummy Track
                    // (FavoritesStore.toggle needs a Track — use the stored data)
                    let dummy = Track(id: track.id, index: track.index ?? 0, name: track.name,
                                     durationSec: track.durationSec, sizeBytes: 0,
                                     streamUrl: "", downloadUrl: "", downloaded: true)
                    let dummyAlbum = AlbumSummary(id: track.albumId, title: track.albumTitle,
                                                   platform: track.platform, year: track.year,
                                                   albumType: "", trackCount: 0, coverUrls: [])
                    favorites.toggle(dummy, album: dummyAlbum)
                }
        }
        .padding(.horizontal, VGSpace.md)
        .padding(.vertical, 10)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .onHover { isHovered = $0 }

        Divider().overlay(Color.vgSeparator).padding(.horizontal, VGSpace.md)
    }
}

private extension FavoriteTrack {
    var index: Int? { nil } // not stored; use track name ordering
}
