import Foundation
import Observation

@Observable
final class PlaylistsStore {
    private(set) var playlists: [PlaylistSummary] = []
    private(set) var isLoading = false
    private var cache: [String: PlaylistDetail] = [:]

    func load() async {
        isLoading = true
        defer { isLoading = false }
        playlists = (try? await APIClient.shared.playlists()) ?? []
    }

    func detail(id: String) async throws -> PlaylistDetail {
        if let cached = cache[id] { return cached }
        let d = try await APIClient.shared.playlist(id: id)
        cache[id] = d
        return d
    }

    func invalidate(id: String) {
        cache.removeValue(forKey: id)
    }

    func create(name: String, description: String = "", isPublic: Bool = false) async throws -> PlaylistSummary {
        let pl = try await APIClient.shared.createPlaylist(name: name, description: description, isPublic: isPublic)
        playlists.insert(pl, at: 0)
        return pl
    }

    func update(id: String, name: String, description: String, isPublic: Bool) async throws {
        try await APIClient.shared.updatePlaylist(id: id, name: name, description: description, isPublic: isPublic)
        playlists = playlists.map { p in
            guard p.id == id else { return p }
            return PlaylistSummary(id: p.id, name: name, description: description, isPublic: isPublic,
                                   trackCount: p.trackCount, totalDurationSec: p.totalDurationSec,
                                   coverUrls: p.coverUrls, ownerId: p.ownerId,
                                   ownerName: p.ownerName, createdAt: p.createdAt)
        }
        invalidate(id: id)
    }

    func delete(id: String) async throws {
        try await APIClient.shared.deletePlaylist(id: id)
        playlists.removeAll { $0.id == id }
        invalidate(id: id)
    }

    func addTrack(playlistId: String, trackId: String) async throws {
        try await APIClient.shared.addTrackToPlaylist(playlistId: playlistId, trackId: trackId)
        playlists = playlists.map { p in
            guard p.id == playlistId else { return p }
            return PlaylistSummary(id: p.id, name: p.name, description: p.description,
                                   isPublic: p.isPublic, trackCount: p.trackCount + 1,
                                   totalDurationSec: p.totalDurationSec, coverUrls: p.coverUrls,
                                   ownerId: p.ownerId, ownerName: p.ownerName, createdAt: p.createdAt)
        }
        invalidate(id: playlistId)
    }

    func removeTrack(playlistId: String, trackId: String) async throws {
        try await APIClient.shared.removeTrackFromPlaylist(playlistId: playlistId, trackId: trackId)
        playlists = playlists.map { p in
            guard p.id == playlistId else { return p }
            return PlaylistSummary(id: p.id, name: p.name, description: p.description,
                                   isPublic: p.isPublic, trackCount: max(0, p.trackCount - 1),
                                   totalDurationSec: p.totalDurationSec, coverUrls: p.coverUrls,
                                   ownerId: p.ownerId, ownerName: p.ownerName, createdAt: p.createdAt)
        }
        invalidate(id: playlistId)
    }

    func myPlaylists(userId: String) -> [PlaylistSummary] {
        playlists.filter { $0.ownerId == userId }
    }
}
