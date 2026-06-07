import SwiftUI

struct AlbumDetailView: View {
    let summary: AlbumSummary
    let onBack: () -> Void

    @Environment(PlayerService.self) var player
    @Environment(FavoritesStore.self) var favorites
    @Environment(HiddenTracksStore.self) var hidden
    @State private var album: Album?
    @State private var isLoading = true
    @State private var hoveredTrackID: String?
    @State private var showLightbox = false
    @State private var downloadingTrackID: String?
    @State private var downloadedIDs: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
        .overlay {
            if showLightbox, let album {
                CoverLightbox(
                    covers: album.covers,
                    title: album.title,
                    initialIndex: CoverPrefsStore.shared.index(for: summary.id),
                    onClose: { showLightbox = false }
                )
            }
        }
    }

    @ViewBuilder
    private func albumContent(_ album: Album) -> some View {
        // Hero header
        HStack(alignment: .top, spacing: 24) {
            AlbumCoverView(
                covers: album.covers,
                title: album.title,
                size: VGLayout.albumCoverDetail,
                initialIndex: CoverPrefsStore.shared.index(for: summary.id),
                onIndexChange: {
                    player.currentCoverIndex = $0
                    CoverPrefsStore.shared.set($0, for: summary.id)
                },
                onTap: { showLightbox = true }
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(album.albumType.isEmpty ? "SOUNDTRACK" : album.albumType.uppercased())
                    .font(VGFont.label(10))
                    .tracking(1.4)
                    .foregroundStyle(Color.vgTextMuted)

                Text(album.title)
                    .font(VGFont.display(30))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                // Alt titles (Japanese, etc.)
                let altLines = album.altTitle.split(separator: "\n").map(String.init)
                if !altLines.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(altLines, id: \.self) { line in
                            Text(line)
                                .font(VGFont.body(12))
                                .foregroundStyle(Color.vgTextSec)
                        }
                    }
                }

                // Platform pills + year
                HStack(spacing: 6) {
                    let platforms = album.platform.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    ForEach(platforms.prefix(4), id: \.self) { p in
                        PlatformPill(platform: p)
                    }
                    if album.year > 0 {
                        Text("·").foregroundStyle(Color.vgTextMuted)
                        Text(String(album.year))
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextSec)
                    }
                }

                metaRow(album)

                Spacer(minLength: 12)

                // Actions
                HStack(spacing: 10) {
                    Button {
                        let playable = album.tracks.filter { downloadedIDs.contains($0.id) && !hidden.isHidden($0.id) }
                        if let first = playable.first ?? album.tracks.first(where: { downloadedIDs.contains($0.id) }) {
                            player.play(track: first, in: summary, queue: playable, covers: album.covers)
                            player.currentCoverIndex = CoverPrefsStore.shared.index(for: summary.id)
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

                    if !album.covers.isEmpty {
                        CircleIconButton(icon: "arrow.down.circle") {
                            Task { await downloadCoversZip(album.covers, title: album.title) }
                        }
                        .help(album.covers.count > 1 ? "Download all covers as ZIP" : "Download cover")
                    }

                    // Star: adds/removes all tracks for this album
                    let allFav = favorites.isAlbumFavorited(summary.id)
                    Button {
                        if allFav {
                            favorites.removeAll(albumID: summary.id)
                        } else {
                            favorites.addAll(album.tracks, album: summary)
                        }
                    } label: {
                        Image(systemName: allFav ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundStyle(allFav ? Color.vgStar : Color.vgTextSec)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.05))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

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

        // Tracklist
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("#").frame(width: 40, alignment: .center)
                Text("TITLE").frame(maxWidth: .infinity, alignment: .leading)
                Text("DUR").frame(width: 60, alignment: .trailing)
                Text("👍").frame(width: 40, alignment: .center)
                Text("👁").frame(width: 40, alignment: .center)
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
                    isPlaying: player.currentTrack?.id == track.id,
                    isDownloaded: downloadedIDs.contains(track.id),
                    isDownloading: downloadingTrackID == track.id,
                    onDownload: { downloadTrack(track) }
                )
                .onHover { hoveredTrackID = $0 ? track.id : nil }
                .onTapGesture(count: 2) {
                    guard downloadedIDs.contains(track.id) else { return }
                    let playable = album.tracks.filter { downloadedIDs.contains($0.id) }
                    player.play(track: track, in: summary, queue: playable, covers: album.covers)
                    player.currentCoverIndex = CoverPrefsStore.shared.index(for: summary.id)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.vgBorder60))
        .background(Color.vgSurface.opacity(0.4).clipShape(RoundedRectangle(cornerRadius: 10)))
        .padding(.horizontal, 32)
        .padding(.bottom, 32)
    }

    @ViewBuilder
    private func metaRow(_ album: Album) -> some View {
        let items: [(String, String)] = [
            ("person.fill",    album.developer),
            ("building.fill",  album.publisher),
            ("barcode",        album.catalogNumber),
        ].filter { !$0.1.isEmpty }

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(items, id: \.0) { icon, value in
                    HStack(spacing: 5) {
                        Image(systemName: icon)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.vgTextMuted)
                            .frame(width: 14)
                        Text(value)
                            .font(VGFont.caption(12))
                            .foregroundStyle(Color.vgTextSec)
                    }
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        let a = try? await APIClient.shared.album(summary.id)
        album = a
        downloadedIDs = Set(a?.tracks.filter(\.downloaded).map(\.id) ?? [])
        isLoading = false
    }

    private func downloadTrack(_ track: Track) {
        guard downloadingTrackID == nil else { return }
        downloadingTrackID = track.id
        Task {
            try? await APIClient.shared.fetchTrack(track.id)
            downloadedIDs.insert(track.id)
            downloadingTrackID = nil
        }
    }

    private func downloadCoversZip(_ covers: [Cover], title: String) async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var filePaths: [String] = []
        for (i, cover) in covers.enumerated() {
            guard let url = AlbumCoverView.resolveURL(cover.url) else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                let file = tempDir.appendingPathComponent(String(format: "cover-%02d.%@", i + 1, ext))
                try? data.write(to: file)
                filePaths.append(file.path)
            }
        }
        guard !filePaths.isEmpty else { return }

        let safeName = String(title.prefix(50)).replacingOccurrences(of: "/", with: "-")
        let outURL: URL
        if covers.count == 1, let ext = filePaths.first.map({ URL(fileURLWithPath: $0).pathExtension }) {
            outURL = FileManager.default.temporaryDirectory.appendingPathComponent("cover.\(ext)")
            try? FileManager.default.copyItem(atPath: filePaths[0], toPath: outURL.path)
        } else {
            outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-covers.zip")
            try? FileManager.default.removeItem(at: outURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-j", outURL.path] + filePaths
            try? process.run()
            process.waitUntilExit()
        }

        await MainActor.run {
            _ = NSWorkspace.shared.selectFile(outURL.path, inFileViewerRootedAtPath: "")
        }
    }
}

// MARK: - Cover lightbox

private struct CoverLightbox: View {
    let covers: [Cover]
    let title: String
    let initialIndex: Int
    let onClose: () -> Void

    @State private var index = 0
    @State private var isDownloading = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.88)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                if !covers.isEmpty {
                    let safeIdx = min(index, covers.count - 1)
                    if let url = AlbumCoverView.resolveURL(covers[safeIdx].url) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                    .shadow(color: .black.opacity(0.6), radius: 40)
                            default:
                                AlbumLetterArt(title: title, size: 480)
                            }
                        }
                        .frame(maxWidth: 560, maxHeight: 560)
                    }
                }

                if covers.count > 1 {
                    HStack(spacing: 24) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { index = max(0, index - 1) }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(index > 0 ? 1 : 0.3)

                        HStack(spacing: 6) {
                            ForEach(0..<covers.count, id: \.self) { i in
                                Circle()
                                    .fill(i == index ? Color.white : Color.white.opacity(0.3))
                                    .frame(width: 6, height: 6)
                                    .onTapGesture { withAnimation { index = i } }
                            }
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) { index = min(covers.count - 1, index + 1) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.white.opacity(0.12))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(index < covers.count - 1 ? 1 : 0.3)
                    }
                }

                Button {
                    guard !isDownloading else { return }
                    Task { await downloadZip() }
                } label: {
                    HStack(spacing: 6) {
                        if isDownloading {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.65)
                            Text("Downloading…")
                        } else {
                            Image(systemName: "arrow.down.circle")
                            Text(covers.count > 1 ? "Download all \(covers.count) covers as ZIP" : "Download cover")
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(isDownloading ? 0.07 : 0.14))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(48)

            // Close button — top right
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(20)
        }
        .onAppear { index = min(initialIndex, max(0, covers.count - 1)) }
        .background {
            Button("") { onClose() }
                .keyboardShortcut(.escape, modifiers: [])
                .hidden()
        }
    }

    private func downloadZip() async {
        isDownloading = true
        defer { Task { @MainActor in isDownloading = false } }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var filePaths: [String] = []
        for (i, cover) in covers.enumerated() {
            guard let url = AlbumCoverView.resolveURL(cover.url) else { continue }
            if let (data, _) = try? await URLSession.shared.data(from: url) {
                let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
                let file = tempDir.appendingPathComponent(String(format: "cover-%02d.%@", i + 1, ext))
                try? data.write(to: file)
                filePaths.append(file.path)
            }
        }
        guard !filePaths.isEmpty else { return }

        let safeName = String(title.prefix(50)).replacingOccurrences(of: "/", with: "-")
        let outURL: URL
        if covers.count == 1 {
            let ext = URL(fileURLWithPath: filePaths[0]).pathExtension
            outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-cover.\(ext)")
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.copyItem(atPath: filePaths[0], toPath: outURL.path)
        } else {
            outURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(safeName)-covers.zip")
            try? FileManager.default.removeItem(at: outURL)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            process.arguments = ["-j", outURL.path] + filePaths
            try? process.run()
            process.waitUntilExit()
        }

        await MainActor.run {
            NSWorkspace.shared.selectFile(outURL.path, inFileViewerRootedAtPath: "")
        }
    }
}

// MARK: - Cover image (real or letter fallback)

struct AlbumCoverView: View {
    let covers: [Cover]
    let title: String
    let size: CGFloat
    var initialIndex: Int = 0
    var enableHoverControls = true
    var onIndexChange: ((Int) -> Void)? = nil
    var onTap: (() -> Void)? = nil

    @State private var coverIndex = 0
    @State private var isHovered = false

    static func resolveURL(_ path: String) -> URL? {
        if path.hasPrefix("http") { return URL(string: path) }
        return URL(string: APIClient.shared.baseURL + path)
    }

    var body: some View {
        let safeIndex = covers.isEmpty ? -1 : min(coverIndex, covers.count - 1)
        ZStack {
            Group {
                if safeIndex >= 0, let url = Self.resolveURL(covers[safeIndex].url) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: size, height: size)
                        default:
                            AlbumLetterArt(title: title, size: size)
                        }
                    }
                } else {
                    AlbumLetterArt(title: title, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .onTapGesture { onTap?() }
            // allowsHitTesting(false) when no tap handler so parent gestures (library card) still fire
            .allowsHitTesting(onTap != nil)

            if enableHoverControls && isHovered && covers.count > 1 {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.45))
                    .frame(width: size, height: size)

                HStack {
                    Button {
                        let newIdx = max(0, coverIndex - 1)
                        withAnimation(.easeInOut(duration: 0.15)) { coverIndex = newIdx }
                        onIndexChange?(newIdx)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(coverIndex > 0 ? 1 : 0.3)

                    Spacer()

                    Button {
                        let newIdx = min(covers.count - 1, coverIndex + 1)
                        withAnimation(.easeInOut(duration: 0.15)) { coverIndex = newIdx }
                        onIndexChange?(newIdx)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.black.opacity(0.55))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .opacity(coverIndex < covers.count - 1 ? 1 : 0.3)
                }
                .padding(.horizontal, 8)
                .frame(width: size)

                VStack {
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(0..<covers.count, id: \.self) { i in
                            Circle()
                                .fill(i == coverIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 5, height: 5)
                        }
                    }
                    .padding(.bottom, 8)
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.vgAccent.opacity(0.15), radius: 20, y: 8)
        .onHover { isHovered = $0 }
        .onAppear { coverIndex = min(initialIndex, max(0, covers.count - 1)) }
    }
}

// MARK: - Track row

private struct DetailTrackRow: View {
    let track: Track
    let album: AlbumSummary
    let isAltRow: Bool
    let isHovered: Bool
    let isPlaying: Bool
    let isDownloaded: Bool
    let isDownloading: Bool
    let onDownload: () -> Void
    @Environment(FavoritesStore.self) var favorites
    @Environment(HiddenTracksStore.self) var hidden

    private var isHidden: Bool { hidden.isHidden(track.id) }
    private var isFav: Bool { favorites.isFavorite(track.id) }

    var body: some View {
        ZStack(alignment: .leading) {
            if isPlaying {
                Color.vgAccentBg
                Color.vgAccent.frame(width: 2)
            } else if isHovered && !isHidden {
                Color.white.opacity(0.04)
            } else if isAltRow {
                Color.white.opacity(0.015)
            }

            HStack(spacing: 0) {
                // Index / state indicator
                Group {
                    if isHidden {
                        Image(systemName: "eye.slash")
                            .foregroundStyle(Color.vgTextMuted).font(.system(size: 11))
                    } else if isPlaying {
                        Image(systemName: "waveform")
                            .foregroundStyle(Color.vgAccent).font(.system(size: 12))
                    } else if isHovered && isDownloaded {
                        Image(systemName: "play.fill")
                            .foregroundStyle(Color.vgText).font(.system(size: 11))
                    } else {
                        Text(String(format: "%02d", track.index))
                            .font(VGFont.mono(12))
                            .foregroundStyle(isDownloaded ? Color.vgTextMuted : Color.vgTextMuted.opacity(0.4))
                    }
                }
                .frame(width: 40, alignment: .center)

                Text(track.name)
                    .font(VGFont.body(13))
                    .foregroundStyle(
                        isHidden ? Color.vgTextMuted :
                        isPlaying ? Color.vgAccent :
                        isDownloaded ? Color.vgText : Color.vgTextSec.opacity(0.5)
                    )
                    .strikethrough(isHidden, color: Color.vgTextMuted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(track.durationFormatted)
                    .font(VGFont.mono(12))
                    .foregroundStyle(isDownloaded ? (isHidden ? Color.vgTextMuted.opacity(0.5) : Color.vgTextSec) : Color.vgTextMuted.opacity(0.3))
                    .frame(width: 60, alignment: .trailing)
                    .monospacedDigit()

                // Download button (when not downloaded) or thumbs up (when downloaded)
                if !isDownloaded {
                    Button(action: onDownload) {
                        Group {
                            if isDownloading {
                                ProgressView().progressViewStyle(.circular).scaleEffect(0.5)
                            } else if isHovered {
                                Image(systemName: "arrow.down.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.vgAccent)
                            } else {
                                Color.clear
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, alignment: .center)
                    .disabled(isDownloading)
                    .help("Download track")
                } else {
                    Button { favorites.toggle(track, album: album) } label: {
                        Group {
                            if isHovered || isFav {
                                Image(systemName: isFav ? "hand.thumbsup.fill" : "hand.thumbsup")
                                    .font(.system(size: 12))
                                    .foregroundStyle(isFav ? Color.vgStar : Color.vgTextSec)
                                    .scaleEffect(isFav ? 1.1 : 1)
                            } else {
                                Color.clear
                            }
                        }
                        .animation(.spring(response: 0.2), value: isFav)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 40, alignment: .center)
                }

                Button { hidden.toggle(track.id) } label: {
                    Image(systemName: isHidden ? "eye.slash.fill" : "arrow.down.to.line")
                        .font(.system(size: 12))
                        .foregroundStyle(isHidden ? Color.vgAccent.opacity(0.7) : isHovered ? Color.vgTextSec : Color.clear)
                }
                .buttonStyle(.plain)
                .frame(width: 40, alignment: .center)
                .help(isHidden ? "Mostrar en reproducción automática" : "Ocultar de reproducción automática")
            }
            .padding(.horizontal, 12)
            .opacity(isHidden ? 0.45 : 1)
        }
        .frame(height: VGLayout.trackRowHeight)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 12)
                .onEnded { v in
                    if v.translation.height > 20 && abs(v.translation.width) < 40 {
                        hidden.toggle(track.id)
                    }
                }
        )
    }
}

// MARK: - Helpers

private struct CircleIconButton: View {
    let icon: String
    var action: (() -> Void)? = nil

    var body: some View {
        Button { action?() } label: {
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
