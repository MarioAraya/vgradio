import SwiftUI

struct PlayerBarView: View {
    @Environment(PlayerService.self) var player
    @Environment(FavoritesStore.self) var favorites
    @State private var isShuffle = false
    @State private var isRepeat = false

    var body: some View {
        ZStack {
            // Glass bar: backdrop blur via .ultraThinMaterial layer + tinted overlay
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.7)
            Color.vgSidebar.opacity(0.6)

            HStack(spacing: 0) {
                leftColumn
                centerColumn
                rightColumn
            }
            .padding(.horizontal, 16)
        }
        .frame(height: VGLayout.playerBarHeight)
        .overlay(alignment: .top) {
            Divider().overlay(Color.vgSeparator)
        }
    }

    // MARK: Left — art + info (fixed 280pt)

    private var leftColumn: some View {
        HStack(spacing: 10) {
            // Album art 44×44
            Group {
                if let album = player.currentAlbum {
                    AlbumLetterArt(title: album.title, size: VGLayout.albumCoverPlayer)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.vgSurface)
                        .frame(width: VGLayout.albumCoverPlayer, height: VGLayout.albumCoverPlayer)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.name ?? "Nothing playing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
                Text(player.currentAlbum?.title ?? "—")
                    .font(VGFont.caption(11))
                    .foregroundStyle(Color.vgTextSec)
                    .lineLimit(1)
            }

            if let track = player.currentTrack, let album = player.currentAlbum {
                Button {
                    let t = Track(id: track.id, index: track.index, name: track.name,
                                  durationSec: track.durationSec, sizeBytes: track.sizeBytes,
                                  streamUrl: track.streamUrl, downloadUrl: track.downloadUrl)
                    favorites.toggle(t, album: album)
                } label: {
                    Image(systemName: favorites.isFavorite(track.id) ? "star.fill" : "star")
                        .font(.system(size: 12))
                        .foregroundStyle(favorites.isFavorite(track.id) ? Color.vgStar : Color.vgTextMuted)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .frame(width: 280, alignment: .leading)
    }

    // MARK: Center — transport + scrubber

    private var centerColumn: some View {
        VStack(spacing: 6) {
            HStack(spacing: 20) {
                TransportButton(icon: "shuffle", size: 14, active: isShuffle) { isShuffle.toggle() }
                TransportButton(icon: "backward.fill", size: 16) { player.previous() }
                PlayPauseButton(isPlaying: player.isPlaying) { player.togglePlay() }
                TransportButton(icon: "forward.fill", size: 16) { player.next() }
                TransportButton(icon: "repeat", size: 14, active: isRepeat) { isRepeat.toggle() }
            }

            HStack(spacing: 6) {
                Text(formatTime(player.currentTime))
                    .font(VGFont.mono(10))
                    .foregroundStyle(Color.vgTextMuted)
                    .frame(width: 36, alignment: .trailing)
                    .monospacedDigit()

                ThinProgressTrack(
                    fraction: player.duration > 0 ? player.currentTime / player.duration : 0
                ) { frac in
                    player.seek(to: frac * player.duration)
                }

                Text(formatTime(player.duration))
                    .font(VGFont.mono(10))
                    .foregroundStyle(Color.vgTextMuted)
                    .frame(width: 36, alignment: .leading)
                    .monospacedDigit()
            }
            .frame(width: 340)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Right — volume (fixed 160pt)

    private var rightColumn: some View {
        @Bindable var playerB = player
        return HStack(spacing: 6) {
            Spacer()
            Button {
                player.isMuted.toggle()
            } label: {
                Image(systemName: player.isMuted || player.volume == 0
                      ? "speaker.slash.fill"
                      : player.volume < 0.4 ? "speaker.wave.1" : "speaker.wave.2")
                    .font(.system(size: 11))
                    .foregroundStyle(player.isMuted ? Color.vgAccent : Color.vgTextMuted)
            }
            .buttonStyle(.plain)

            ThinProgressTrack(fraction: player.isMuted ? 0 : player.volume) { frac in
                player.volume = frac
            }
            .frame(width: 88)
        }
        .frame(width: 160, alignment: .trailing)
    }

    private func formatTime(_ secs: Double) -> String {
        guard secs.isFinite, secs >= 0 else { return "0:00" }
        let s = Int(secs)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Transport controls

private struct TransportButton: View {
    let icon: String
    var size: CGFloat = 14
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
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
                .font(.system(size: 14))
                .foregroundStyle(Color.vgBg)
                .frame(width: VGLayout.playBtnSize, height: VGLayout.playBtnSize)
                .background(Color.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
