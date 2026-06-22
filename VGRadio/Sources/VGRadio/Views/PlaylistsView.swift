import SwiftUI

// MARK: - Liked Music (auto-playlist backed by FavoritesStore)

struct LikedMusicView: View {
    @Environment(FavoritesStore.self) var favorites
    @Environment(PlayerService.self) var player

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VGSpace.lg) {
                // Hero header
                HStack(alignment: .bottom, spacing: VGSpace.lg) {
                    PlaylistMosaicView(coverURLs: favorites.grouped.prefix(4).compactMap { $0.coverUrl.isEmpty ? nil : $0.coverUrl }, size: 140)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("AUTO PLAYLIST")
                            .font(VGFont.label(10))
                            .tracking(1.2)
                            .foregroundStyle(Color.vgTextMuted)
                        Text("Liked Music")
                            .font(VGFont.display(28))
                            .foregroundStyle(Color.vgText)
                        Text("\(favorites.favorites.count) tracks")
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextSec)
                        if !favorites.favorites.isEmpty {
                            Button { playAll() } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.fill").font(.system(size: 11))
                                    Text("Play all").font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(Color.vgBg)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 7)
                                .background(Color.vgAccent)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 4)
                        }
                    }
                    Spacer()
                }
                .padding(.top, VGSpace.md)
                .padding(.horizontal, VGSpace.xl)

                if favorites.grouped.isEmpty {
                    VStack(spacing: VGSpace.md) {
                        Image(systemName: "star").font(.system(size: 40)).foregroundStyle(Color.vgTextMuted)
                        Text("No liked tracks yet").font(VGFont.heading()).foregroundStyle(Color.vgTextSec)
                        Text("Tap 👍 on any track to add it here.").font(VGFont.body()).foregroundStyle(Color.vgTextMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
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

    private func playAll() {
        let tracks = favorites.favorites.enumerated().map { i, f in
            Track(id: f.id, index: i + 1, name: f.name, durationSec: f.durationSec,
                  sizeBytes: 0, streamUrl: "/tracks/\(f.id)/stream",
                  downloadUrl: "/tracks/\(f.id)/download", downloaded: true)
        }
        guard let first = tracks.first else { return }
        let album = AlbumSummary(id: "__liked__", title: "Liked Music", platform: "", year: 0,
                                  albumType: "", trackCount: tracks.count, totalDurationSec: 0, coverUrls: [])
        player.play(track: first, in: album, queue: tracks)
    }
}

// MARK: - Playlist Detail

struct PlaylistDetailView: View {
    let playlistId: String
    @Environment(PlayerService.self) var player
    @Environment(PlaylistsStore.self) var store
    @Environment(AuthStore.self) var auth

    @State private var detail: PlaylistDetail?
    @State private var isLoading = true
    @State private var error = ""
    @State private var showEdit = false
    @State private var hoveredTrackId: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                } else if !error.isEmpty {
                    Text(error).foregroundStyle(Color.vgTextMuted).padding(.top, 80).frame(maxWidth: .infinity)
                } else if let pl = detail {
                    heroHeader(pl)
                    trackList(pl)
                }
            }
            .padding(.bottom, VGSpace.xl)
        }
        .background(Color.vgBg)
        .task { await load() }
        .sheet(isPresented: $showEdit) {
            if let pl = detail {
                PlaylistEditSheet(
                    name: pl.name,
                    description: pl.description,
                    isPublic: pl.isPublic,
                    onSave: { name, desc, pub in
                        Task {
                            try? await store.update(id: pl.id, name: name, description: desc, isPublic: pub)
                            await load()
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private func heroHeader(_ pl: PlaylistDetail) -> some View {
        HStack(alignment: .bottom, spacing: VGSpace.lg) {
            PlaylistMosaicView(coverURLs: pl.coverUrls, size: 140)

            VStack(alignment: .leading, spacing: 5) {
                Text((pl.isPublic ? "PUBLIC" : "PRIVATE") + " PLAYLIST · \(pl.createdAt.prefix(4))")
                    .font(VGFont.label(10))
                    .tracking(1.2)
                    .foregroundStyle(Color.vgTextMuted)

                Text(pl.name)
                    .font(VGFont.display(28))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(2)

                if !pl.description.isEmpty {
                    Text(pl.description)
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgTextSec)
                        .lineLimit(2)
                }

                Text("@\(pl.ownerName)  ·  \(pl.trackCount) tracks\(pl.totalDurationSec > 0 ? "  ·  \(pl.totalDurationFormatted)" : "")")
                    .font(VGFont.caption())
                    .foregroundStyle(Color.vgTextSec)

                HStack(spacing: 10) {
                    if !pl.tracks.isEmpty {
                        Button { playAll(pl) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "play.fill").font(.system(size: 11))
                                Text("Play").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Color.vgBg)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 7)
                            .background(Color.vgAccent)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    if auth.currentUser?.id == pl.ownerId {
                        Button { showEdit = true } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.vgTextSec)
                                .frame(width: 32, height: 32)
                                .background(Color.white.opacity(0.06))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Edit playlist")
                    }
                }
                .padding(.top, 4)
            }
            Spacer()
        }
        .padding(.top, VGSpace.md)
        .padding(.horizontal, VGSpace.xl)
        .padding(.bottom, VGSpace.lg)
    }

    @ViewBuilder
    private func trackList(_ pl: PlaylistDetail) -> some View {
        let isOwner = auth.currentUser?.id == pl.ownerId
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("#").frame(width: 40, alignment: .center)
                Text("TITLE").frame(maxWidth: .infinity, alignment: .leading)
                Text("ALBUM").frame(width: 160, alignment: .leading)
                Text("DUR").frame(width: 60, alignment: .trailing)
                if isOwner { Color.clear.frame(width: 40) }
            }
            .font(VGFont.label(10))
            .tracking(1.0)
            .foregroundStyle(Color.vgTextMuted)
            .frame(height: 32)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.02))

            ForEach(Array(pl.tracks.enumerated()), id: \.element.id) { idx, track in
                PlaylistTrackRow(
                    track: track,
                    position: idx + 1,
                    isOwner: isOwner,
                    isHovered: hoveredTrackId == track.id,
                    isPlaying: player.currentTrack?.id == track.id,
                    onPlay: { playFrom(pl, track: track) },
                    onRemove: {
                        Task {
                            try? await store.removeTrack(playlistId: pl.id, trackId: track.id)
                            await load()
                        }
                    }
                )
                .onHover { hoveredTrackId = $0 ? track.id : nil }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.vgBorder60))
        .background(Color.vgSurface.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 10)))
        .padding(.horizontal, VGSpace.xl)

        if pl.tracks.isEmpty {
            Text("No tracks yet. Add tracks from an album.")
                .font(VGFont.body())
                .foregroundStyle(Color.vgTextMuted)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        }
    }

    private func playAll(_ pl: PlaylistDetail) {
        let queue = pl.tracks.enumerated().map { $0.element.asTrack(index: $0.offset + 1) }
        guard let first = queue.first else { return }
        let summary = AlbumSummary(id: pl.id, title: pl.name, platform: "", year: 0,
                                    albumType: "", trackCount: pl.trackCount,
                                    totalDurationSec: pl.totalDurationSec, coverUrls: pl.coverUrls)
        player.play(track: first, in: summary, queue: queue)
    }

    private func playFrom(_ pl: PlaylistDetail, track: PlaylistTrack) {
        let queue = pl.tracks.enumerated().map { $0.element.asTrack(index: $0.offset + 1) }
        let t = queue.first(where: { $0.id == track.id }) ?? queue[0]
        let summary = AlbumSummary(id: pl.id, title: pl.name, platform: "", year: 0,
                                    albumType: "", trackCount: pl.trackCount,
                                    totalDurationSec: pl.totalDurationSec, coverUrls: pl.coverUrls)
        player.play(track: t, in: summary, queue: queue)
    }

    private func load() async {
        isLoading = true
        error = ""
        store.invalidate(id: playlistId)
        do {
            detail = try await store.detail(id: playlistId)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Playlist track row

private struct PlaylistTrackRow: View {
    let track: PlaylistTrack
    let position: Int
    let isOwner: Bool
    let isHovered: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            if isPlaying {
                Color.vgAccentBg
                Color.vgAccent.frame(width: 2)
            } else if isHovered {
                Color.white.opacity(0.04)
            }

            HStack(spacing: 0) {
                Group {
                    if isPlaying {
                        Image(systemName: "waveform").foregroundStyle(Color.vgAccent).font(.system(size: 12))
                    } else if isHovered {
                        Image(systemName: "play.fill").foregroundStyle(Color.vgText).font(.system(size: 11))
                    } else {
                        Text("\(position)").font(VGFont.mono(12)).foregroundStyle(Color.vgTextMuted)
                    }
                }
                .frame(width: 40, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.name)
                        .font(VGFont.body(13))
                        .foregroundStyle(isPlaying ? Color.vgAccent : Color.vgText)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(track.albumTitle)
                    .font(VGFont.caption(12))
                    .foregroundStyle(Color.vgTextSec)
                    .lineLimit(1)
                    .frame(width: 160, alignment: .leading)

                Text(track.durationFormatted)
                    .font(VGFont.mono(12))
                    .foregroundStyle(Color.vgTextSec)
                    .frame(width: 60, alignment: .trailing)
                    .monospacedDigit()

                if isOwner {
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(isHovered ? Color.vgTextSec : Color.clear)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, alignment: .center)
                    .help("Remove from playlist")
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: VGLayout.trackRowHeight)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onPlay() }

        Divider().overlay(Color.vgSeparator)
    }
}

// MARK: - Mosaic cover (2x2 grid of playlist covers)

struct PlaylistMosaicView: View {
    let coverURLs: [String]
    let size: CGFloat

    var body: some View {
        let urls = coverURLs.prefix(4)
        ZStack {
            if urls.isEmpty {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.vgSurfaceHi)
                    .frame(width: size, height: size)
                Image(systemName: "music.note.list")
                    .font(.system(size: size * 0.3))
                    .foregroundStyle(Color.vgTextSec)
            } else if urls.count == 1 {
                AsyncCoverImage(url: resolveURL(String(urls[0])), size: size)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                let half = size / 2
                LazyVGrid(columns: [GridItem(.fixed(half)), GridItem(.fixed(half))], spacing: 0) {
                    ForEach(Array(urls.enumerated()), id: \.offset) { _, url in
                        AsyncCoverImage(url: resolveURL(String(url)), size: half)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.vgAccent.opacity(0.12), radius: 16, y: 6)
    }

    private func resolveURL(_ path: String) -> URL? {
        AlbumCoverView.resolveURL(path)
    }
}

private struct AsyncCoverImage: View {
    let url: URL?
    let size: CGFloat
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().aspectRatio(contentMode: .fill).frame(width: size, height: size).clipped()
            default:
                Color.vgSurfaceHi.frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Edit sheet

struct PlaylistEditSheet: View {
    @Environment(\.dismiss) var dismiss
    var name: String
    var description: String
    var isPublic: Bool
    let onSave: (String, String, Bool) -> Void

    @State private var editName = ""
    @State private var editDesc = ""
    @State private var editPublic = false

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.lg) {
            Text(editName.isEmpty ? "New Playlist" : editName)
                .font(VGFont.title())
                .foregroundStyle(Color.vgText)

            VStack(alignment: .leading, spacing: 6) {
                Text("TITLE").font(VGFont.label(10)).tracking(1).foregroundStyle(Color.vgTextMuted)
                TextField("Playlist name", text: $editName)
                    .textFieldStyle(.roundedBorder)
                    .font(VGFont.body())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("DESCRIPTION").font(VGFont.label(10)).tracking(1).foregroundStyle(Color.vgTextMuted)
                TextField("Description (optional)", text: $editDesc)
                    .textFieldStyle(.roundedBorder)
                    .font(VGFont.body())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PRIVACY").font(VGFont.label(10)).tracking(1).foregroundStyle(Color.vgTextMuted)
                Picker("", selection: $editPublic) {
                    Text("Private").tag(false)
                    Text("Public").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .foregroundStyle(Color.vgTextSec)
                Button("Save") {
                    onSave(editName.trimmingCharacters(in: .whitespaces), editDesc, editPublic)
                    dismiss()
                }
                .disabled(editName.trimmingCharacters(in: .whitespaces).isEmpty)
                .foregroundStyle(Color.vgBg)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(editName.isEmpty ? Color.vgAccent.opacity(0.4) : Color.vgAccent)
                .clipShape(Capsule())
            }
        }
        .padding(VGSpace.xl)
        .frame(width: 400)
        .background(Color.vgSurface)
        .onAppear {
            editName = name
            editDesc = description
            editPublic = isPublic
        }
    }
}

// MARK: - Add to Playlist picker

struct AddToPlaylistSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(PlaylistsStore.self) var store
    @Environment(AuthStore.self) var auth
    let trackId: String
    var onAdded: (() -> Void)? = nil

    @State private var newName = ""
    @State private var adding = false
    @State private var statusMsg = ""

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.lg) {
            Text("Add to Playlist")
                .font(VGFont.heading())
                .foregroundStyle(Color.vgText)

            let myLists = auth.currentUser.map { store.myPlaylists(userId: $0.id) } ?? []

            if myLists.isEmpty {
                Text("No playlists yet.")
                    .font(VGFont.body())
                    .foregroundStyle(Color.vgTextSec)
            } else {
                VStack(spacing: 2) {
                    ForEach(myLists) { pl in
                        Button {
                            Task { await addTo(pl) }
                        } label: {
                            HStack {
                                Text(pl.name).font(VGFont.body()).foregroundStyle(Color.vgText)
                                Spacer()
                                Text("\(pl.trackCount)").font(VGFont.caption()).foregroundStyle(Color.vgTextSec)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Color.white.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().overlay(Color.vgSeparator)

            HStack(spacing: 8) {
                TextField("New playlist name…", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .font(VGFont.body())
                Button("+") {
                    Task { await createAndAdd() }
                }
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || adding)
                .foregroundStyle(Color.vgAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.vgAccentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !statusMsg.isEmpty {
                Text(statusMsg).font(VGFont.caption()).foregroundStyle(Color.vgTextSec)
            }

            HStack {
                Spacer()
                Button("Close") { dismiss() }.foregroundStyle(Color.vgTextSec)
            }
        }
        .padding(VGSpace.xl)
        .frame(width: 340)
        .background(Color.vgSurface)
    }

    private func addTo(_ pl: PlaylistSummary) async {
        adding = true
        do {
            try await store.addTrack(playlistId: pl.id, trackId: trackId)
            statusMsg = "Added to \"\(pl.name)\""
            onAdded?()
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            statusMsg = "Already in playlist or error"
        }
        adding = false
    }

    private func createAndAdd() async {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        adding = true
        do {
            let pl = try await store.create(name: name)
            try await store.addTrack(playlistId: pl.id, trackId: trackId)
            statusMsg = "Added to new playlist \"\(pl.name)\""
            newName = ""
            onAdded?()
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            statusMsg = "Error: \(error.localizedDescription)"
        }
        adding = false
    }
}

// MARK: - FavoriteGroupView (reused from FavoritesView)

private struct FavoriteGroupView: View {
    let group: (albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [FavoriteTrack])

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: VGSpace.md) {
                AsyncCoverImage(url: AlbumCoverView.resolveURL(group.coverUrl), size: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.albumTitle).font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.vgText)
                    Text("\(group.platform)  ·  \(group.year)").font(VGFont.mono(11)).foregroundStyle(Color.vgTextSec)
                }
                Spacer()
            }
            .padding(.bottom, VGSpace.sm)

            VStack(spacing: 0) {
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
                    LikedTrackRow(track: track)
                }
            }
            .background(Color.vgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct LikedTrackRow: View {
    let track: FavoriteTrack
    @Environment(FavoritesStore.self) var favorites
    @State private var isHovered = false

    var body: some View {
        HStack {
            Text(String(format: "%02d", 0))
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
            Image(systemName: "star.fill")
                .foregroundStyle(Color.vgStar)
                .frame(width: 28, alignment: .center)
                .onTapGesture {
                    let dummy = Track(id: track.id, index: 0, name: track.name,
                                     durationSec: track.durationSec, sizeBytes: 0,
                                     streamUrl: "", downloadUrl: "", downloaded: true)
                    let dummyAlbum = AlbumSummary(id: track.albumId, title: track.albumTitle,
                                                   platform: track.platform, year: track.year,
                                                   albumType: "", trackCount: 0, totalDurationSec: 0, coverUrls: [])
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
