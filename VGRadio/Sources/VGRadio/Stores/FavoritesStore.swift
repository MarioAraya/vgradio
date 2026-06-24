import Foundation
import Observation

@Observable
final class FavoritesStore {
    private(set) var favorites: [FavoriteTrack] = []

    func isFavorite(_ trackID: String) -> Bool {
        favorites.contains(where: { $0.id == trackID })
    }

    func toggle(_ track: Track, album: AlbumSummary) {
        // Optimistic update
        if isFavorite(track.id) {
            favorites.removeAll(where: { $0.id == track.id })
        } else {
            favorites.insert(FavoriteTrack(
                id: track.id, name: track.name,
                albumId: album.id, albumTitle: album.title,
                platform: album.platform, year: album.year,
                durationSec: track.durationSec, coverUrl: album.coverUrls.first
            ), at: 0)
        }
        Task { try? await APIClient.shared.toggleTrackFavorite(id: track.id) }
    }

    func toggleByID(_ trackID: String) {
        if let idx = favorites.firstIndex(where: { $0.id == trackID }) {
            favorites.remove(at: idx)
        }
        Task { try? await APIClient.shared.toggleTrackFavorite(id: trackID) }
    }

    func isAlbumFavorited(_ albumID: String) -> Bool {
        favorites.contains(where: { $0.albumId == albumID })
    }

    func removeAll(albumID: String) {
        let ids = favorites.filter { $0.albumId == albumID }.map { $0.id }
        favorites.removeAll(where: { $0.albumId == albumID })
        for id in ids {
            Task { try? await APIClient.shared.toggleTrackFavorite(id: id) }
        }
    }

    func addAll(_ tracks: [Track], album: AlbumSummary) {
        for track in tracks where !isFavorite(track.id) {
            favorites.insert(FavoriteTrack(
                id: track.id, name: track.name,
                albumId: album.id, albumTitle: album.title,
                platform: album.platform, year: album.year,
                durationSec: track.durationSec, coverUrl: album.coverUrls.first
            ), at: 0)
            Task { try? await APIClient.shared.toggleTrackFavorite(id: track.id) }
        }
    }

    func load() async {
        favorites = (try? await APIClient.shared.favoriteTracks()) ?? []
    }

    func clear() {
        favorites = []
    }

    var grouped: [(albumId: String, albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [FavoriteTrack])] {
        var seen: [String: Int] = [:]
        var groups: [(albumId: String, albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [FavoriteTrack])] = []
        for f in favorites {
            if let idx = seen[f.albumId] {
                groups[idx].tracks.append(f)
            } else {
                seen[f.albumId] = groups.count
                groups.append((f.albumId, f.albumTitle, f.platform, f.year, f.coverUrl ?? "", [f]))
            }
        }
        return groups
    }
}
