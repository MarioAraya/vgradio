import SwiftUI

struct QueuePanel: View {
    @Environment(PlayerService.self) var player

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Queue")
                    .font(VGFont.heading())
                    .foregroundStyle(Color.vgText)
                Spacer()
                Text("\(player.queue.count) tracks")
                    .font(VGFont.caption(11))
                    .foregroundStyle(Color.vgTextMuted)
                Button { player.showQueue = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.vgTextMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.vgHoverMd)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider().overlay(Color.vgSeparator)

            if player.queue.isEmpty {
                Text("Queue is empty")
                    .font(VGFont.body())
                    .foregroundStyle(Color.vgTextMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 40)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(player.queue.indices, id: \.self) { i in
                            QueueRow(
                                track: player.queue[i].track,
                                playlistTitle: player.queue[i].album.title,
                                index: i,
                                isCurrent: i == player.queueIndex,
                                onPlay: { player.playAt(index: i) },
                                onRemove: { player.removeFromQueue(at: i) }
                            )
                            .id(i)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onMove { player.moveInQueue(from: $0, to: $1) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onAppear {
                        proxy.scrollTo(player.queueIndex, anchor: .center)
                    }
                    .onChange(of: player.queueIndex) { _, idx in
                        withAnimation { proxy.scrollTo(idx, anchor: .center) }
                    }
                }
            }
        }
        .frame(width: 320, height: 420)
        .background(Color.vgSidebar.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.vgBorder60))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
    }
}

private struct QueueRow: View {
    let track: Track
    let playlistTitle: String?
    let index: Int
    let isCurrent: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void
    @State private var isHovered = false

    /// The playlist row shows the real source album next to the playlist
    /// name (e.g. Liked Music mixes tracks from many albums); when the
    /// container itself IS the album (a regular album queue), skip the
    /// redundant "Title — Title" repeat.
    private var subtitle: String? {
        guard let playlistTitle else { return track.sourceAlbumTitle }
        guard let albumTitle = track.sourceAlbumTitle, albumTitle != playlistTitle else { return playlistTitle }
        return "\(playlistTitle) · \(albumTitle)"
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.vgAccent)
                } else {
                    Text(String(format: "%02d", index + 1))
                        .font(VGFont.mono(11))
                        .foregroundStyle(Color.vgTextMuted)
                }
            }
            .frame(width: 24, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.name)
                    .font(VGFont.body(13))
                    .foregroundStyle(isCurrent ? Color.vgAccent : Color.vgText)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(VGFont.caption(10))
                        .foregroundStyle(Color.vgTextMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(track.durationFormatted)
                .font(VGFont.mono(11))
                .foregroundStyle(Color.vgTextMuted)
                .monospacedDigit()

            if isHovered && !isCurrent {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.vgTextMuted)
                        .frame(width: 20, height: 20)
                        .background(Color.vgHoverMd)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            } else {
                Color.clear.frame(width: 20, height: 20)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(height: 50)
        .background(isCurrent ? Color.vgAccentBg : isHovered ? Color.vgHover : Color.clear)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPlay() }
    }
}
