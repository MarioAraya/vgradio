import SwiftUI

struct PlayerBarView: View {
    @Environment(PlayerService.self) var player
    @Environment(FavoritesStore.self) var favorites
    @State private var isShuffle = false
    @State private var isRepeat = false

    var body: some View {
        @Bindable var playerB = player

        HStack(spacing: 0) {
            // Left: art + track info
            HStack(spacing: VGSpace.md) {
                Group {
                    if let album = player.currentAlbum {
                        AlbumLetterArt(title: album.title, size: 40)
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.vgSurface)
                            .frame(width: 40, height: 40)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentTrack?.name ?? "Nothing playing")
                        .font(VGFont.body(13))
                        .fontWeight(.medium)
                        .foregroundStyle(Color.vgText)
                        .lineLimit(1)
                    Text(player.currentAlbum?.title ?? "Select an album")
                        .font(VGFont.caption())
                        .foregroundStyle(Color.vgTextSec)
                        .lineLimit(1)
                }

                // Favorite toggle for current track
                if let track = player.currentTrack, let album = player.currentAlbum {
                    Button {
                        let t = Track(id: track.id, index: track.index, name: track.name,
                                      durationSec: track.durationSec, sizeBytes: track.sizeBytes,
                                      streamUrl: track.streamUrl, downloadUrl: track.downloadUrl)
                        favorites.toggle(t, album: album)
                    } label: {
                        Image(systemName: favorites.isFavorite(track.id) ? "heart.fill" : "heart")
                            .foregroundStyle(favorites.isFavorite(track.id) ? Color.vgAccent : Color.vgTextMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Center: transport + scrubber
            VStack(spacing: VGSpace.sm) {
                HStack(spacing: VGSpace.lg) {
                    TransportButton(icon: "shuffle", active: isShuffle) { isShuffle.toggle() }
                    TransportButton(icon: "backward.fill") { player.previous() }
                    PlayPauseButton(isPlaying: player.isPlaying) { player.togglePlay() }
                    TransportButton(icon: "forward.fill") { player.next() }
                    TransportButton(icon: "repeat", active: isRepeat) { isRepeat.toggle() }
                }

                HStack(spacing: VGSpace.sm) {
                    Text(formatTime(player.currentTime))
                        .font(VGFont.mono(11))
                        .foregroundStyle(Color.vgTextMuted)
                        .frame(width: 36, alignment: .trailing)

                    Slider(
                        value: Binding(
                            get: { player.duration > 0 ? player.currentTime / player.duration : 0 },
                            set: { player.seek(to: $0 * player.duration) }
                        )
                    )
                    .tint(Color.vgAccent)
                    .frame(width: 260)

                    Text(formatTime(player.duration))
                        .font(VGFont.mono(11))
                        .foregroundStyle(Color.vgTextMuted)
                        .frame(width: 36, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)

            // Right: volume
            HStack(spacing: VGSpace.sm) {
                Image(systemName: "speaker.wave.2")
                    .foregroundStyle(Color.vgTextMuted)
                    .font(.system(size: 12))
                Slider(value: .constant(0.8))
                    .tint(Color.vgAccent)
                    .frame(width: 90)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, VGSpace.xl)
        .padding(.vertical, VGSpace.md)
        .background(Color.vgSidebar)
        .frame(height: 80)
    }

    private func formatTime(_ secs: Double) -> String {
        guard secs.isFinite, secs >= 0 else { return "0:00" }
        let s = Int(secs)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Subviews

private struct TransportButton: View {
    let icon: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(active ? Color.vgAccent : Color.vgTextSec)
        }
        .buttonStyle(.plain)
    }
}

private struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.vgBg)
                .frame(width: 40, height: 40)
                .background(Color.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
