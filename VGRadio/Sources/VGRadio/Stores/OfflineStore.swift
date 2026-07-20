import Foundation
import Observation
import Network
import AppKit

/// Manages tracks downloaded to a user-chosen folder on this Mac, and whether
/// playback should prefer those local files over streaming from the backend.
@MainActor
@Observable
final class OfflineStore {
    private(set) var downloadedTracks: [DownloadedTrack] = []
    var downloadedTrackIDs: Set<String> { Set(downloadedTracks.map(\.id)) }
    private(set) var isBackendReachable = true
    var offlineModeEnabled: Bool {
        didSet { UserDefaults.standard.set(offlineModeEnabled, forKey: modeKey) }
    }
    private(set) var downloadingTrackIDs: Set<String> = []

    /// True when playback should be restricted to locally downloaded tracks —
    /// either the user turned it on, or the backend isn't reachable right now.
    var effectiveOfflineMode: Bool { offlineModeEnabled || !isBackendReachable }

    private let modeKey = "vgradio.offline.enabled"
    private let bookmarkKey = "vgradio.offline.folderBookmark"
    private let filesKey = "vgradio.offline.files"

    private var folderURL: URL?
    private var pathMonitor: NWPathMonitor?
    private var healthTimer: Timer?

    init() {
        offlineModeEnabled = UserDefaults.standard.bool(forKey: modeKey)
        loadFolderBookmark()
        loadDownloadedIDs()
        migrateLegacyFileNames()
    }

    // MARK: - Folder

    var hasFolder: Bool { folderURL != nil }

    var folderDisplayPath: String {
        folderURL?.path ?? "No configurada"
    }

    func revealFolderInFinder() {
        guard let folderURL else { return }
        NSWorkspace.shared.open(folderURL)
    }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir carpeta"
        panel.message = "Elegí dónde guardar las canciones descargadas para escuchar offline"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderURL = url
        saveFolderBookmark(url)
    }

    private func loadFolderBookmark() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
            folderURL = url
        }
    }

    private func saveFolderBookmark(_ url: URL) {
        guard let data = try? url.bookmarkData(options: [.withSecurityScope]) else { return }
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    // MARK: - Downloaded files

    private func loadDownloadedIDs() {
        if let data = UserDefaults.standard.data(forKey: filesKey),
           let tracks = try? JSONDecoder().decode([DownloadedTrack].self, from: data) {
            downloadedTracks = tracks
            return
        }
        // Legacy format: plain string array of track IDs, no metadata. Migrate
        // in place so previously-downloaded files don't vanish from the list.
        if let ids = UserDefaults.standard.stringArray(forKey: filesKey), !ids.isEmpty {
            downloadedTracks = ids.map { id in
                DownloadedTrack(id: id, index: 0, name: id, albumId: "",
                                 albumTitle: "Descargas antiguas", platform: "", year: 0,
                                 durationSec: 0, coverUrl: nil)
            }
            saveDownloadedIDs()
        }
    }

    private func saveDownloadedIDs() {
        guard let data = try? JSONEncoder().encode(downloadedTracks) else { return }
        UserDefaults.standard.set(data, forKey: filesKey)
    }

    func localURL(for trackID: String) -> URL? {
        guard let folderURL, let track = downloadedTracks.first(where: { $0.id == trackID }) else { return nil }
        let file = folderURL.appendingPathComponent(track.resolvedFileName)
        return FileManager.default.fileExists(atPath: file.path) ? file : nil
    }

    /// Sanitizes a string for use as a path component (no "/" or ":", trimmed, capped length).
    private static func sanitizeForFilename(_ s: String) -> String {
        let cleaned = s.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let capped = cleaned.count > 80 ? String(cleaned.prefix(80)) : cleaned
        return capped.isEmpty ? "Untitled" : capped
    }

    /// Builds a human-readable, collision-free filename for a track being downloaded.
    private func uniqueFileName(albumTitle: String, trackName: String) -> String {
        let base = "\(Self.sanitizeForFilename(albumTitle)) - \(Self.sanitizeForFilename(trackName))"
        let existing = Set(downloadedTracks.map(\.resolvedFileName))
        var candidate = "\(base).mp3"
        var n = 2
        while existing.contains(candidate) {
            candidate = "\(base) (\(n)).mp3"
            n += 1
        }
        return candidate
    }

    /// Renames already-downloaded files from the old "<trackId>.mp3" scheme to
    /// human-readable "Album - Track.mp3" names, one time, so files dropped
    /// into the offline folder before this change also become legible in Finder.
    private func migrateLegacyFileNames() {
        guard let folderURL else { return }
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }
        var changed = false
        for i in downloadedTracks.indices {
            guard downloadedTracks[i].fileName == nil, downloadedTracks[i].albumTitle != "Descargas antiguas" else { continue }
            let track = downloadedTracks[i]
            let oldPath = folderURL.appendingPathComponent("\(track.id).mp3")
            guard FileManager.default.fileExists(atPath: oldPath.path) else { continue }
            let newName = uniqueFileName(albumTitle: track.albumTitle, trackName: track.name)
            let newPath = folderURL.appendingPathComponent(newName)
            do {
                try FileManager.default.moveItem(at: oldPath, to: newPath)
                downloadedTracks[i].fileName = newName
                changed = true
            } catch {
                // best-effort; leave this one under its legacy name
            }
        }
        if changed { saveDownloadedIDs() }
    }

    func isDownloaded(_ trackID: String) -> Bool { localURL(for: trackID) != nil }

    /// Number of tracks downloaded locally for a given album.
    func downloadedCount(albumID: String) -> Int {
        downloadedTracks.filter { $0.albumId == albumID }.count
    }

    /// True when every track of the album (per `totalTracks`) is downloaded locally.
    func isAlbumDownloaded(albumID: String, totalTracks: Int) -> Bool {
        totalTracks > 0 && downloadedCount(albumID: albumID) >= totalTracks
    }

    func downloadOffline(_ track: Track, album: AlbumSummary) async {
        guard let folderURL else { return }
        guard let remoteURL = APIClient.shared.streamURL(for: track) else { return }
        downloadingTrackIDs.insert(track.id)
        defer { downloadingTrackIDs.remove(track.id) }

        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        let fileName = uniqueFileName(albumTitle: album.title, trackName: track.name)
        do {
            let (tmpURL, _) = try await URLSession.shared.download(from: remoteURL)
            let dest = folderURL.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmpURL, to: dest)
            downloadedTracks.removeAll(where: { $0.id == track.id })
            downloadedTracks.insert(DownloadedTrack(
                id: track.id, index: track.index, name: track.name,
                albumId: album.id, albumTitle: album.title,
                platform: album.platform, year: album.year,
                durationSec: track.durationSec, coverUrl: album.coverUrls.first,
                fileName: fileName
            ), at: 0)
            saveDownloadedIDs()
        } catch {
            // best-effort; track simply stays not-downloaded
        }
    }

    func removeOffline(_ trackID: String) {
        if let url = localURL(for: trackID) {
            try? FileManager.default.removeItem(at: url)
        }
        downloadedTracks.removeAll(where: { $0.id == trackID })
        saveDownloadedIDs()
    }

    /// Removes every locally-downloaded track belonging to an album (frees disk space).
    func removeAllOffline(albumID: String) {
        for id in downloadedTracks.filter({ $0.albumId == albumID }).map(\.id) {
            if let url = localURL(for: id) {
                try? FileManager.default.removeItem(at: url)
            }
        }
        downloadedTracks.removeAll(where: { $0.albumId == albumID })
        saveDownloadedIDs()
    }

    var offlineStorageBytes: Int64 {
        guard let folderURL else { return 0 }
        return downloadedTracks.reduce(Int64(0)) { total, t in
            let file = folderURL.appendingPathComponent(t.resolvedFileName)
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            return total + size
        }
    }

    func offlineStorageBytes(albumID: String) -> Int64 {
        guard let folderURL else { return 0 }
        return downloadedTracks.filter { $0.albumId == albumID }.reduce(Int64(0)) { total, t in
            let file = folderURL.appendingPathComponent(t.resolvedFileName)
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? 0
            return total + size
        }
    }

    var grouped: [(albumId: String, albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [DownloadedTrack])] {
        var seen: [String: Int] = [:]
        var groups: [(albumId: String, albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [DownloadedTrack])] = []
        for t in downloadedTracks {
            if let idx = seen[t.albumId] {
                groups[idx].tracks.append(t)
            } else {
                seen[t.albumId] = groups.count
                groups.append((t.albumId, t.albumTitle, t.platform, t.year, t.coverUrl ?? "", [t]))
            }
        }
        return groups
    }

    // MARK: - Reachability

    func startMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if path.status != .satisfied {
                    self.isBackendReachable = false
                } else {
                    await self.checkBackendHealth()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        pathMonitor = monitor

        healthTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.checkBackendHealth() }
        }
        Task { await checkBackendHealth() }
    }

    func stopMonitoring() {
        pathMonitor?.cancel()
        pathMonitor = nil
        healthTimer?.invalidate()
        healthTimer = nil
    }

    private func checkBackendHealth() async {
        isBackendReachable = await APIClient.shared.healthCheck()
    }
}
