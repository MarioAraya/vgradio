import Foundation
import Observation

@Observable
final class FavoritesStore {
    private(set) var favorites: [FavoriteTrack] = []

    private let key = "vgradio.favorites"

    init() { load() }

    func isFavorite(_ trackID: String) -> Bool {
        favorites.contains(where: { $0.id == trackID })
    }

    func toggle(_ track: Track, album: AlbumSummary) {
        if isFavorite(track.id) {
            favorites.removeAll(where: { $0.id == track.id })
        } else {
            favorites.append(FavoriteTrack(
                id: track.id,
                name: track.name,
                albumId: album.id,
                albumTitle: album.title,
                platform: album.platform,
                year: album.year,
                durationSec: track.durationSec,
                coverUrl: album.coverUrls.first
            ))
        }
        save()
    }

    func isAlbumFavorited(_ albumID: String) -> Bool {
        favorites.contains(where: { $0.albumId == albumID })
    }

    func removeAll(albumID: String) {
        favorites.removeAll(where: { $0.albumId == albumID })
        save()
    }

    func addAll(_ tracks: [Track], album: AlbumSummary) {
        for track in tracks where !isFavorite(track.id) {
            favorites.append(FavoriteTrack(
                id: track.id,
                name: track.name,
                albumId: album.id,
                albumTitle: album.title,
                platform: album.platform,
                year: album.year,
                durationSec: track.durationSec,
                coverUrl: album.coverUrls.first
            ))
        }
        save()
    }

    /// Tracks grouped by album, preserving insertion order.
    var grouped: [(albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [FavoriteTrack])] {
        var seen: [String: Int] = [:]
        var groups: [(albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [FavoriteTrack])] = []
        for f in favorites {
            if let idx = seen[f.albumId] {
                groups[idx].tracks.append(f)
            } else {
                seen[f.albumId] = groups.count
                groups.append((f.albumTitle, f.platform, f.year, f.coverUrl ?? "", [f]))
            }
        }
        return groups
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([FavoriteTrack].self, from: data)
        else { return }
        favorites = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
