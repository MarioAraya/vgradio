import SwiftUI

struct PlayerBarView: View {
    @Environment(PlayerService.self) var player
    @Environment(FavoritesStore.self) var favorites
    @Environment(LibraryStore.self) var library
    @Environment(HiddenTracksStore.self) var hidden
    @Environment(ConnectService.self) var connect
    @State private var isVolumeHovered = false
    @State private var showAddToPlaylist = false
    @State private var addToPlaylistTrackIds: [String] = []
    @State private var addToPlaylistDefaultName: String?

    // While another device owns playback the bar is a remote control, so what it
    // draws comes from the hub's state instead of the local AVPlayer.
    private var remote: ConnectState? { connect.isRemote ? connect.remoteState : nil }

    private var barTrack: Track? { remote != nil ? connect.remoteTrack : player.currentTrack }
    private var barAlbum: AlbumSummary? { remote != nil ? connect.remoteAlbum : player.currentAlbum }
    private var barCovers: [Cover] { remote != nil ? connect.remoteCovers : player.currentCovers }
    private var barCoverIndex: Int { remote?.coverIndex ?? player.currentCoverIndex }
    private var barPosition: Double { remote != nil ? connect.remotePosition : player.currentTime }
    private var barDuration: Double { remote != nil ? Double(barTrack?.durationSec ?? 0) : player.duration }
    private var barIsPlaying: Bool { remote?.isPlaying ?? player.isPlaying }
    private var barIsMuted: Bool { remote?.isMuted ?? player.isMuted }
    private var barVolume: Double { remote?.volume ?? player.volume }
    private var barIsShuffle: Bool { remote?.isShuffle ?? player.isShuffle }
    private var barRepeat: RepeatMode {
        guard let mode = remote?.repeatMode else { return player.repeatMode }
        return mode == "one" ? .one : mode == "all" ? .all : .off
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.ultraThinMaterial).opacity(0.7)
            Color.vgSidebar.opacity(0.6)

            VStack(spacing: 0) {
                if connect.isRemote {
                    RemoteBannerView()
                }

                // Full-width progress bar flush at top edge
                ThinProgressTrack(
                    fraction: barDuration > 0 ? barPosition / barDuration : 0
                ) { frac in
                    player.seek(to: frac * barDuration)
                }

                // Single row: cover+info LEFT | transport CENTER | volume+actions RIGHT
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .leading) {
                        if barTrack != nil {
                            coverAndInfoSection
                                .padding(.leading, 16)
                        }
                    }
                    .overlay {
                        transportSection
                    }
                    .overlay(alignment: .trailing) {
                        HStack(spacing: 0) {
                            volumeSection
                            DevicePickerView()
                            actionsSection
                            secondarySection
                        }
                        .padding(.trailing, 4)
                    }
            }
        }
        .frame(height: connect.isRemote ? VGLayout.playerBarHeight + VGLayout.remoteBannerHeight : VGLayout.playerBarHeight)
        .sheet(isPresented: $showAddToPlaylist) {
            if !addToPlaylistTrackIds.isEmpty {
                AddToPlaylistSheet(trackIds: addToPlaylistTrackIds, defaultNewPlaylistName: addToPlaylistDefaultName)
            }
        }
    }

    // MARK: – Prev | Play | Next | time

    private var transportSection: some View {
        HStack(spacing: 0) {
            YTTransportButton(icon: "backward.fill", size: 20) { player.previous() }
            PlayPauseButton(isPlaying: barIsPlaying) { player.togglePlay() }
            YTTransportButton(icon: "forward.fill", size: 20) { player.next() }

            if barTrack != nil {
                Text("\(formatTime(barPosition)) / \(formatTime(barDuration))")
                    .font(VGFont.mono(12))
                    .foregroundStyle(Color.vgTextSec)
                    .monospacedDigit()
                    .padding(.leading, 12)
                    .fixedSize()
            }
        }
    }

    // MARK: – Cover + title/album (flexible)

    private var coverAndInfoSection: some View {
        HStack(spacing: 12) {
            // Cover using currentCoverIndex so it mirrors AlbumDetailView selection
            let size = VGLayout.albumCoverPlayer
            let idx = min(barCoverIndex, max(0, barCovers.count - 1))
            Group {
                if !barCovers.isEmpty,
                   let url = AlbumCoverView.resolveURL(barCovers[idx].url) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        default:
                            AlbumLetterArt(title: barAlbum?.title ?? "", size: size)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    .frame(width: size, height: size)
                } else if let album = barAlbum {
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
                Text(barTrack?.name ?? "")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
                Text(barAlbum?.title ?? "—")
                    .font(VGFont.caption(12))
                    .foregroundStyle(Color.vgTextSec)
                    .lineLimit(1)
            }
            .frame(minWidth: 100, maxWidth: 280, alignment: .leading)
            .onTapGesture { navigateToCurrentAlbum() }
            .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
        }
    }

    private func navigateToCurrentAlbum() {
        guard let album = barAlbum else { return }
        library.pendingNavigation = album
    }

    // MARK: – Star / dislike current track

    private var actionsSection: some View {
        Group {
            if let track = barTrack, let album = barAlbum {
                HStack(spacing: 0) {
                    Button {
                        if favorites.isFavorite(track.id) {
                            addToPlaylistTrackIds = [track.id]
                            addToPlaylistDefaultName = track.name
                            showAddToPlaylist = true
                        } else {
                            favorites.toggle(track, album: album)
                        }
                    } label: {
                        Image(systemName: favorites.isFavorite(track.id) ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundStyle(favorites.isFavorite(track.id) ? Color.vgStar : Color.vgTextMuted)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Dislike: hide the track so the queue skips it from now on, and
                    // jump to the next playable one right away.
                    Button {
                        hidden.toggle(track.id)
                        if hidden.isHidden(track.id) { player.next() }
                    } label: {
                        Image(systemName: hidden.isHidden(track.id) ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                            .font(.system(size: 15))
                            .foregroundStyle(hidden.isHidden(track.id) ? Color.vgAccent : Color.vgTextMuted)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("No me gusta — ocultar y saltar (⌘⌫)")
                }
            }
        }
    }

    // MARK: – Volume (slider aparece solo on hover)

    private var volumeSection: some View {
        HStack(spacing: isVolumeHovered ? 8 : 0) {
            if isVolumeHovered {
                ThinProgressTrack(fraction: barIsMuted ? 0 : barVolume) { frac in
                    player.setVolume(frac)
                }
                .frame(width: 90)
                .transition(.opacity)
            }

            Button {
                player.toggleMute()
            } label: {
                Image(systemName: barIsMuted || barVolume == 0
                      ? "speaker.slash.fill"
                      : barVolume < 0.4 ? "speaker.wave.1" : "speaker.wave.2")
                    .font(.system(size: 15))
                    .foregroundStyle(barIsMuted ? Color.vgAccent : Color.vgTextMuted)
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
                player.cycleRepeat()
            } label: {
                Image(systemName: barRepeat == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 16))
                    .foregroundStyle(barRepeat == .off ? Color.vgTextSec : Color.vgAccent)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(barRepeat == .off ? "Repeat off" : barRepeat == .all ? "Repeat all" : "Repeat one")

            YTTransportButton(icon: "shuffle", size: 16, active: barIsShuffle) { player.toggleShuffle() }

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
                .background(Color.vgText)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
