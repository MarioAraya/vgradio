import SwiftUI

struct AlbumDetailView: View {
    let summary: AlbumSummary
    let onBack: () -> Void

    @Environment(PlayerService.self) var player
    @Environment(FavoritesStore.self) var favorites
    @State private var album: Album?
    @State private var isLoading = true
    @State private var hoveredTrackID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Back button
                Button { onBack() } label: {
                    Label("Library", systemImage: "chevron.left")
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgAccent)
                }
                .buttonStyle(.plain)
                .padding(.top, VGSpace.xl)
                .padding(.horizontal, VGSpace.xl)

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
        HStack(alignment: .top, spacing: VGSpace.xl) {
            AlbumLetterArt(title: album.title, size: 140)

            VStack(alignment: .leading, spacing: VGSpace.sm) {
                Text(album.albumType.uppercased())
                    .font(VGFont.caption(10))
                    .foregroundStyle(Color.vgTextMuted)

                Text(album.title)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color.vgText)

                if !album.altTitle.isEmpty {
                    Text(album.altTitle)
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgTextSec)
                }

                HStack(spacing: VGSpace.sm) {
                    PlatformPill(platform: album.platform)
                    Text("·").foregroundStyle(Color.vgTextMuted)
                    Text(String(album.year)).font(VGFont.body()).foregroundStyle(Color.vgTextSec)
                    if !album.developer.isEmpty {
                        Text("·").foregroundStyle(Color.vgTextMuted)
                        Text(album.developer).font(VGFont.body()).foregroundStyle(Color.vgTextSec)
                    }
                }

                Spacer()

                HStack(spacing: VGSpace.md) {
                    Button {
                        if let first = album.tracks.first {
                            player.play(track: first, in: summary, queue: album.tracks)
                        }
                    } label: {
                        Label("Play", systemImage: "play.fill")
                            .font(VGFont.heading(13))
                    }
                    .buttonStyle(VGButtonStyle())

                    Text("\(album.tracks.count) tracks")
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgTextMuted)
                }
            }
        }
        .padding(.horizontal, VGSpace.xl)
        .padding(.top, VGSpace.lg)
        .padding(.bottom, VGSpace.xl)

        // Tracklist
        VStack(spacing: 0) {
            // Column headers
            HStack {
                Text("#").frame(width: 36, alignment: .trailing)
                Text("TITLE").frame(maxWidth: .infinity, alignment: .leading)
                Text("DUR").frame(width: 60, alignment: .trailing)
                Text("★").frame(width: 36, alignment: .center)
            }
            .font(VGFont.caption(11))
            .foregroundStyle(Color.vgTextMuted)
            .padding(.horizontal, VGSpace.xl)
            .padding(.vertical, VGSpace.sm)

            Divider().overlay(Color.vgSeparator).padding(.horizontal, VGSpace.xl)

            ForEach(album.tracks) { track in
                TrackRow(
                    track: track,
                    album: summary,
                    isHovered: hoveredTrackID == track.id,
                    isPlaying: player.currentTrack?.id == track.id
                )
                .onHover { hoveredTrackID = $0 ? track.id : nil }
                .onTapGesture(count: 2) {
                    player.play(track: track, in: summary, queue: album.tracks)
                }
                .padding(.horizontal, VGSpace.xl)
            }
        }
        .padding(.bottom, VGSpace.xl)
    }

    private func load() async {
        isLoading = true
        album = try? await APIClient.shared.album(summary.id)
        isLoading = false
    }
}

// MARK: - Track Row

private struct TrackRow: View {
    let track: Track
    let album: AlbumSummary
    let isHovered: Bool
    let isPlaying: Bool
    @Environment(FavoritesStore.self) var favorites

    var body: some View {
        HStack {
            Group {
                if isPlaying {
                    Image(systemName: "waveform")
                        .foregroundStyle(Color.vgAccent)
                } else if isHovered {
                    Image(systemName: "play.fill")
                        .foregroundStyle(Color.vgText)
                } else {
                    Text(String(format: "%02d", track.index))
                        .font(VGFont.mono())
                        .foregroundStyle(Color.vgTextMuted)
                }
            }
            .frame(width: 36, alignment: .trailing)

            Text(track.name)
                .font(VGFont.body())
                .foregroundStyle(isPlaying ? Color.vgAccent : Color.vgText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.durationFormatted)
                .font(VGFont.mono())
                .foregroundStyle(Color.vgTextSec)
                .frame(width: 60, alignment: .trailing)

            Button {
                favorites.toggle(track, album: album)
            } label: {
                Image(systemName: favorites.isFavorite(track.id) ? "star.fill" : "star")
                    .foregroundStyle(favorites.isFavorite(track.id) ? Color.vgStar : Color.vgTextMuted)
            }
            .buttonStyle(.plain)
            .frame(width: 36, alignment: .center)
        }
        .padding(.vertical, 9)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
    }
}
