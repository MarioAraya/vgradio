import SwiftUI

struct RecentlyPlayedView: View {
    @Environment(PlayerService.self) var player
    @Environment(LibraryStore.self) var library
    @State private var entries: [HistoryEntry] = []
    @State private var isLoading = true

    private static let dateFormatter = ISO8601DateFormatter()
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private func timeAgo(_ iso: String) -> String {
        guard let date = Self.dateFormatter.date(from: iso) else { return "" }
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func play(_ entry: HistoryEntry) {
        let track = Track(id: entry.trackId, index: 0, name: entry.trackName,
                          durationSec: 0, sizeBytes: 0,
                          streamUrl: "/tracks/\(entry.trackId)/stream",
                          downloadUrl: "/tracks/\(entry.trackId)/download")
        let album = AlbumSummary(id: entry.albumId, title: entry.albumTitle, platform: entry.platform,
                                 year: entry.year, albumType: "", trackCount: 0, totalDurationSec: 0,
                                 coverUrls: entry.coverUrl.isEmpty ? [] : [entry.coverUrl])
        player.play(track: track, in: album, queue: [track])
    }

    private func openAlbum(_ entry: HistoryEntry) {
        library.pendingNavigation = AlbumSummary(
            id: entry.albumId, title: entry.albumTitle, platform: entry.platform, year: entry.year,
            albumType: "", trackCount: 0, totalDurationSec: 0,
            coverUrls: entry.coverUrl.isEmpty ? [] : [entry.coverUrl]
        )
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                Text("Recently Played")
                    .font(VGFont.title())
                    .foregroundStyle(Color.vgText)
                    .padding(.top, VGSpace.md)
                    .padding(.horizontal, VGSpace.xl)
                    .padding(.bottom, VGSpace.lg)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    ForEach(entries) { entry in
                        RecentlyPlayedRow(entry: entry, timeAgo: timeAgo(entry.playedAt),
                                          onPlay: { play(entry) }, onOpenAlbum: { openAlbum(entry) })
                    }
                    .padding(.horizontal, VGSpace.xl)
                }
            }
            .padding(.bottom, VGSpace.xl)
        }
        .background(Color.vgBg)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        entries = (try? await APIClient.shared.history(limit: 100)) ?? []
        isLoading = false
    }

    private var emptyState: some View {
        VStack(spacing: VGSpace.md) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(Color.vgTextMuted)
            Text("No hay historial todavía")
                .font(VGFont.heading())
                .foregroundStyle(Color.vgTextSec)
            Text("Las canciones que reproduzcas van a aparecer acá.")
                .font(VGFont.body())
                .foregroundStyle(Color.vgTextMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

private struct RecentlyPlayedRow: View {
    let entry: HistoryEntry
    let timeAgo: String
    let onPlay: () -> Void
    let onOpenAlbum: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: VGSpace.md) {
            AsyncImage(url: AlbumCoverView.resolveURL(entry.coverUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: AlbumLetterArt(title: entry.albumTitle, size: 44)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .onTapGesture(perform: onOpenAlbum)
            .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.trackName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onPlay)
                Text(entry.albumTitle)
                    .font(VGFont.caption(12))
                    .foregroundStyle(Color.vgTextSec)
                    .lineLimit(1)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onOpenAlbum)
                    .onHover { inside in inside ? NSCursor.pointingHand.push() : NSCursor.pop() }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.platform)\(entry.platform.isEmpty || entry.year == 0 ? "" : "  ·  ")\(entry.year > 0 ? String(entry.year) : "")")
                    .font(VGFont.caption(11))
                    .foregroundStyle(Color.vgTextMuted)
                Text(timeAgo)
                    .font(VGFont.caption(11))
                    .foregroundStyle(Color.vgTextMuted)
            }
        }
        .padding(.horizontal, VGSpace.sm)
        .padding(.vertical, 6)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { isHovered = $0 }
    }
}
