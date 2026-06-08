import SwiftUI

struct PlayerBarView: View {
    @Environment(PlayerService.self) var player
    @Environment(FavoritesStore.self) var favorites
    @Environment(LibraryStore.self) var library
    @State private var isVolumeHovered = false

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial).opacity(0.7)
            Color.vgSidebar.opacity(0.6)

            VStack(spacing: 0) {
                // Full-width progress bar flush at top edge
                ThinProgressTrack(
                    fraction: player.duration > 0 ? player.currentTime / player.duration : 0
                ) { frac in
                    player.seek(to: frac * player.duration)
                }

                // Single row
                HStack(spacing: 0) {
                    transportSection
                    coverAndInfoSection
                    Spacer(minLength: 8)
                    volumeSection
                    actionsSection
                    secondarySection
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
            }
        }
        .frame(height: VGLayout.playerBarHeight)
    }

    // MARK: – Prev | Play | Next | time

    private var transportSection: some View {
        HStack(spacing: 0) {
            YTTransportButton(icon: "backward.fill", size: 20) { player.previous() }
            PlayPauseButton(isPlaying: player.isPlaying) { player.togglePlay() }
            YTTransportButton(icon: "forward.fill", size: 20) { player.next() }

            Text("\(formatTime(player.currentTime)) / \(formatTime(player.duration))")
                .font(VGFont.mono(12))
                .foregroundStyle(Color.vgTextSec)
                .monospacedDigit()
                .padding(.leading, 12)
                .fixedSize()
        }
    }

    // MARK: – Cover + title/album (flexible)

    private var coverAndInfoSection: some View {
        HStack(spacing: 12) {
            // Cover using currentCoverIndex so it mirrors AlbumDetailView selection
            let size = VGLayout.albumCoverPlayer
            let idx = min(player.currentCoverIndex, max(0, player.currentCovers.count - 1))
            Group {
                if !player.currentCovers.isEmpty,
                   let url = AlbumCoverView.resolveURL(player.currentCovers[idx].url) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            AlbumLetterArt(title: player.currentAlbum?.title ?? "", size: size)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(width: size, height: size)
                } else if let album = player.currentAlbum {
                    AlbumLetterArt(title: album.title, size: size)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.vgSurface)
                        .frame(width: size, height: size)
                }
            }
            .onTapGesture { navigateToCurrentAlbum() }
            .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }

            VStack(alignment: .leading, spacing: 2) {
                Text(player.currentTrack?.name ?? "Nothing playing")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
                Text(player.currentAlbum?.title ?? "—")
                    .font(VGFont.caption(12))
                    .foregroundStyle(Color.vgTextSec)
                    .lineLimit(1)
            }
            .frame(minWidth: 100, maxWidth: 280, alignment: .leading)
            .onTapGesture { navigateToCurrentAlbum() }
            .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
        }
        .padding(.leading, 16)
    }

    private func navigateToCurrentAlbum() {
        guard let album = player.currentAlbum else { return }
        library.pendingNavigation = album
    }

    // MARK: – Star current track

    private var actionsSection: some View {
        Group {
            if let track = player.currentTrack, let album = player.currentAlbum {
                Button {
                    favorites.toggle(track, album: album)
                } label: {
                    Image(systemName: favorites.isFavorite(track.id) ? "star.fill" : "star")
                        .font(.system(size: 16))
                        .foregroundStyle(favorites.isFavorite(track.id) ? Color.vgStar : Color.vgTextMuted)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: – Volume (slider aparece solo on hover)

    private var volumeSection: some View {
        HStack(spacing: isVolumeHovered ? 8 : 0) {
            if isVolumeHovered {
                ThinProgressTrack(fraction: player.isMuted ? 0 : player.volume) { frac in
                    player.volume = frac
                    if frac > 0 { player.isMuted = false }
                }
                .frame(width: 90)
                .transition(.opacity)
            }

            Button {
                player.isMuted.toggle()
            } label: {
                Image(systemName: player.isMuted || player.volume == 0
                      ? "speaker.slash.fill"
                      : player.volume < 0.4 ? "speaker.wave.1" : "speaker.wave.2")
                    .font(.system(size: 15))
                    .foregroundStyle(player.isMuted ? Color.vgAccent : Color.vgTextMuted)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .animation(.easeInOut(duration: 0.18), value: isVolumeHovered)
        .onHover { isVolumeHovered = $0 }
        .padding(.leading, 4)
    }

    // MARK: – Repeat + shuffle

    private var secondarySection: some View {
        HStack(spacing: 0) {
            Button {
                switch player.repeatMode {
                case .off: player.repeatMode = .all
                case .all: player.repeatMode = .one
                case .one: player.repeatMode = .off
                }
            } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 16))
                    .foregroundStyle(player.repeatMode == .off ? Color.vgTextSec : Color.vgAccent)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.repeatMode == .off ? "Repeat off" : player.repeatMode == .all ? "Repeat all" : "Repeat one")

            YTTransportButton(icon: "shuffle", size: 16, active: player.isShuffle) { player.isShuffle.toggle() }

            Button { player.showQueue.toggle() } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15))
                    .foregroundStyle(player.showQueue ? Color.vgAccent : Color.vgTextSec)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Queue")
        }
        .padding(.leading, 4)
    }

    private func formatTime(_ secs: Double) -> String {
        guard secs.isFinite, secs >= 0 else { return "0:00" }
        let s = Int(secs)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Controls

private struct YTTransportButton: View {
    let icon: String
    var size: CGFloat = 16
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size))
                .foregroundStyle(active ? Color.vgAccent : Color.vgTextSec)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
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
                .frame(width: 52, height: 52)
                .background(Color.white)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
