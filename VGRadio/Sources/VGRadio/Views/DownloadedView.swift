import SwiftUI

struct DownloadedView: View {
    @Environment(OfflineStore.self) var offline
    @Environment(PlayerService.self) var player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VGSpace.lg) {
                // Header
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Descargado")
                            .font(VGFont.title())
                            .foregroundStyle(Color.vgText)
                        Text(subtitle)
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextSec)
                    }
                    Spacer()
                    if !offline.downloadedTracks.isEmpty {
                        Button { playAll() } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 11))
                                Text("Play all").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color.vgOnAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 7)
                            .background(Color.vgAccent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Play all downloaded tracks")
                    }
                }
                .padding(.top, VGSpace.md)
                .padding(.horizontal, VGSpace.xl)

                if offline.grouped.isEmpty {
                    emptyState
                } else {
                    ForEach(offline.grouped, id: \.albumTitle) { group in
                        DownloadedGroupView(group: group)
                    }
                    .padding(.horizontal, VGSpace.xl)
                }
            }
            .padding(.bottom, VGSpace.xl)
        }
        .background(Color.vgBg)
    }

    private func playAll() {
        let tracks = offline.downloadedTracks.enumerated().map { i, d in
            Track(id: d.id, index: i + 1, name: d.name,
                  durationSec: d.durationSec, sizeBytes: 0,
                  streamUrl: "/tracks/\(d.id)/stream",
                  downloadUrl: "/tracks/\(d.id)/download",
                  downloaded: true)
        }
        guard let first = tracks.first else { return }
        let album = AlbumSummary(id: "downloaded", title: "Descargado",
                                 platform: "", year: 0, albumType: "",
                                 trackCount: tracks.count, totalDurationSec: 0, coverUrls: [])
        player.play(track: first, in: album, queue: tracks)
    }

    private var subtitle: String {
        let total = offline.downloadedTracks.count
        let albums = offline.grouped.count
        if total == 0 { return "No hay canciones descargadas todavía" }
        return "\(total) canción\(total == 1 ? "" : "es") descargada\(total == 1 ? "" : "s") en \(albums) álbum\(albums == 1 ? "" : "es")"
    }

    private var emptyState: some View {
        VStack(spacing: VGSpace.md) {
            Image(systemName: "checkmark.icloud")
                .font(.system(size: 40))
                .foregroundStyle(Color.vgTextMuted)
            Text("No hay descargas")
                .font(VGFont.heading())
                .foregroundStyle(Color.vgTextSec)
            Text("Descargá canciones para escucharlas sin conexión.")
                .font(VGFont.body())
                .foregroundStyle(Color.vgTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}

// MARK: - Group

private struct DownloadedGroupView: View {
    let group: (albumId: String, albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [DownloadedTrack])
    @Environment(LibraryStore.self) var library

    private func openAlbum() {
        library.pendingNavigation = AlbumSummary(
            id: group.albumId, title: group.albumTitle, platform: group.platform, year: group.year,
            albumType: "", trackCount: group.tracks.count, totalDurationSec: 0,
            coverUrls: group.coverUrl.isEmpty ? [] : [group.coverUrl]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Album header
            HStack(spacing: VGSpace.md) {
                AsyncImage(url: AlbumCoverView.resolveURL(group.coverUrl)) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                    default: AlbumLetterArt(title: group.albumTitle, size: 48)
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture(perform: openAlbum)
                .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.albumTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.vgText)
                    Text("\(group.platform)  ·  \(String(group.year))")
                        .font(VGFont.mono(11))
                        .foregroundStyle(Color.vgTextSec)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: openAlbum)
                .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
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
                    Text("").frame(width: 28, alignment: .center)
                }
                .font(VGFont.caption(11))
                .foregroundStyle(Color.vgTextMuted)
                .padding(.horizontal, VGSpace.md)
                .padding(.vertical, VGSpace.sm)

                Divider().overlay(Color.vgSeparator)

                ForEach(group.tracks.sorted(by: { $0.index < $1.index })) { track in
                    DownloadedTrackRow(track: track, group: group)
                }
            }
            .background(Color.vgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Track row

private struct DownloadedTrackRow: View {
    let track: DownloadedTrack
    let group: (albumId: String, albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [DownloadedTrack])
    @Environment(OfflineStore.self) var offline
    @Environment(PlayerService.self) var player
    @Environment(LibraryStore.self) var library
    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(String(format: "%02d", track.index))
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

            // Remove from offline storage
            Button {
                offline.removeOffline(track.id)
            } label: {
                Image(systemName: "checkmark.icloud.fill")
                    .foregroundStyle(isHovered ? Color.red : Color.green)
            }
            .buttonStyle(.plain)
            .frame(width: 28, alignment: .center)
            .help("Quitar descarga")
        }
        .padding(.horizontal, VGSpace.md)
        .padding(.vertical, 10)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { play() }
        .contextMenu {
            Button { player.playNext(asTrack()) } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }
        }

        Divider().overlay(Color.vgSeparator).padding(.horizontal, VGSpace.md)
    }

    private func asTrack() -> Track {
        Track(id: track.id, index: track.index, name: track.name,
              durationSec: track.durationSec, sizeBytes: 0,
              streamUrl: "/tracks/\(track.id)/stream",
              downloadUrl: "/tracks/\(track.id)/download",
              downloaded: true)
    }

    private func play() {
        var index = 0
        let allTracks: [Track] = offline.grouped.flatMap { g in
            g.tracks.sorted(by: { $0.index < $1.index }).map { d -> Track in
                index += 1
                return Track(id: d.id, index: index, name: d.name,
                             durationSec: d.durationSec, sizeBytes: 0,
                             streamUrl: "/tracks/\(d.id)/stream",
                             downloadUrl: "/tracks/\(d.id)/download",
                             downloaded: true)
            }
        }
        guard let current = allTracks.first(where: { $0.id == track.id }) else { return }
        let resolvedCovers = group.coverUrl.isEmpty
            ? (library.albums.first(where: { $0.id == group.albumId })?.coverUrls ?? [])
            : [group.coverUrl]
        let album = AlbumSummary(id: "downloaded", title: "Descargado",
                                 platform: group.platform, year: group.year,
                                 albumType: "", trackCount: allTracks.count, totalDurationSec: 0, coverUrls: resolvedCovers)
        player.play(track: current, in: album, queue: allTracks)
    }
}
