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
                // Back
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
        // Hero header — px-8 py-6
        HStack(alignment: .top, spacing: 24) {
            AlbumLetterArt(title: album.title, size: VGLayout.albumCoverDetail)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: Color.vgAccent.opacity(0.2), radius: 24, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(album.albumType.isEmpty ? "SOUNDTRACK" : album.albumType.uppercased())
                    .font(VGFont.label(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.vgTextMuted)

                Text(album.title)
                    .font(VGFont.display(34))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(3)

                if !album.altTitle.isEmpty {
                    Text(album.altTitle)
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgTextSec)
                }

                HStack(spacing: 8) {
                    PlatformPill(platform: album.platform)
                    if album.year > 0 {
                        Text("·").foregroundStyle(Color.vgTextMuted)
                        Text(String(album.year))
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextSec)
                    }
                    if !album.developer.isEmpty {
                        Text("·").foregroundStyle(Color.vgTextMuted)
                        Text(album.developer)
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextSec)
                    }
                }

                Spacer(minLength: 16)

                HStack(spacing: 10) {
                    // Primary play button — rounded-full
                    Button {
                        if let first = album.tracks.first {
                            player.play(track: first, in: summary, queue: album.tracks)
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

                    // Action icon buttons — size-9 rounded-full bg-white/5
                    CircleIconButton(icon: "arrow.down.circle")
                    CircleIconButton(icon: "star")
                    CircleIconButton(icon: "square.and.arrow.up")

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

        // Tracklist container — rounded border card/40
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("#")
                    .frame(width: 40, alignment: .center)
                Text("TITLE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("DUR")
                    .frame(width: 60, alignment: .trailing)
                Text("★")
                    .frame(width: 40, alignment: .center)
                Color.clear.frame(width: 40)
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
                    player.play(track: track, in: summary, queue: album.tracks)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.vgBorder60))
        .background(Color.vgSurface.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 10)))
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    private func load() async {
        isLoading = true
        album = try? await APIClient.shared.album(summary.id)
        isLoading = false
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

    var body: some View {
        ZStack(alignment: .leading) {
            // Playing: accent bg + 2px left border
            if isPlaying {
                Color.vgAccentBg
                Color.vgAccent.frame(width: 2)
            } else if isAltRow && !isHovered {
                Color.white.opacity(0.015)
            }
            if isHovered && !isPlaying {
                Color.white.opacity(0.04)
            }

            HStack(spacing: 0) {
                // Index / waveform / play icon
                Group {
                    if isPlaying {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.vgAccent)
                            .font(.system(size: 12))
                    } else if isHovered {
                        Image(systemName: "play.fill")
                            .foregroundStyle(Color.vgText)
                            .font(.system(size: 11))
                    } else {
                        Text(String(format: "%02d", track.index))
                            .font(VGFont.mono(12))
                            .foregroundStyle(Color.vgTextMuted)
                    }
                }
                .frame(width: 40, alignment: .center)

                Text(track.name)
                    .font(VGFont.body(13))
                    .foregroundStyle(isPlaying ? Color.vgAccent : Color.vgText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(track.durationFormatted)
                    .font(VGFont.mono(12))
                    .foregroundStyle(Color.vgTextSec)
                    .frame(width: 60, alignment: .trailing)
                    .monospacedDigit()

                // Star
                Button {
                    favorites.toggle(track, album: album)
                } label: {
                    Image(systemName: favorites.isFavorite(track.id) ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(favorites.isFavorite(track.id) ? Color.vgStar : Color.vgTextMuted)
                        .scaleEffect(favorites.isFavorite(track.id) ? 1.15 : 1)
                        .animation(.spring(response: 0.2), value: favorites.isFavorite(track.id))
                }
                .buttonStyle(.plain)
                .frame(width: 40, alignment: .center)

                // Download (hover only, always shown for layout)
                Button {} label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(isHovered ? Color.vgTextSec : Color.clear)
                }
                .buttonStyle(.plain)
                .frame(width: 40, alignment: .center)
            }
            .padding(.horizontal, 12)
        }
        .frame(height: VGLayout.trackRowHeight)
        .contentShape(Rectangle())
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
