import Foundation

// MARK: - API response models (mirror backend JSON)

struct Album: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var altTitle: String        // newline-separated alternate titles
    var platform: String        // comma-separated: "PS3, PS4, Switch"
    var year: Int
    var developer: String
    var publisher: String
    var catalogNumber: String
    var albumType: String
    var description: String
    var sourceUrl: String
    var covers: [Cover]
    var tracks: [Track]
    var comments: [Comment]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Album, r: Album) -> Bool { l.id == r.id }
}

struct AlbumSummary: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var platform: String
    var year: Int
    var albumType: String
    var trackCount: Int
    var totalDurationSec: Int
    var coverUrls: [String]

    var covers: [Cover] { coverUrls.map { Cover(url: $0, width: 0, height: 0) } }

    var totalDurationFormatted: String {
        guard totalDurationSec > 0 else { return "" }
        let h = totalDurationSec / 3600
        let m = (totalDurationSec % 3600) / 60
        let s = totalDurationSec % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

struct Track: Codable, Identifiable, Hashable {
    let id: String
    var index: Int
    var name: String
    var durationSec: Int
    var sizeBytes: Int
    var streamUrl: String
    var downloadUrl: String
    var downloaded: Bool = false

    var durationFormatted: String {
        let m = durationSec / 60, s = durationSec % 60
        return String(format: "%d:%02d", m, s)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Track, r: Track) -> Bool { l.id == r.id }
}

struct Cover: Codable {
    var url: String
    var width: Int
    var height: Int
}

struct Comment: Codable {
    var author: String
    var body: String
    var postedAt: String
}

// MARK: - Job

struct ScrapeJob: Codable {
    var jobId: String?
    var albumId: String
    var status: JobStatus
    var error: String?

    enum JobStatus: String, Codable {
        case pending, running, done, failed
    }
}

// MARK: - Catalog

struct CatalogEntry: Decodable, Identifiable {
    var title: String
    var sourceUrl: String
    var platform: String
    var albumType: String
    var year: Int
    var id: String { sourceUrl }

    var slug: String { sourceUrl.split(separator: "/").last.map(String.init) ?? "" }
    var thumbnailURL: String? {
        let s = slug
        guard !s.isEmpty else { return nil }
        return "https://nu.vgmtreasurechest.com/soundtracks/\(s)/thumbs_small/folder_itemimage.png"
    }
}

struct CatalogPage: Decodable {
    var total: Int
    var offset: Int
    var limit: Int
    var items: [CatalogEntry]
}

struct CatalogConsole: Decodable, Identifiable {
    var id: String
    var name: String
    var url: String
    var albumCount: Int
}

struct CatalogSyncProgress: Decodable {
    var running: Bool
    var total: Int
    var done: Int
    var errors: Int
    var entries: Int
    var consoles: Int
}

// MARK: - Auth

struct UserProfile: Codable, Identifiable {
    var id: String
    var username: String
    var email: String
}

// MARK: - Playlists

struct PlaylistSummary: Codable, Identifiable {
    var id: String
    var name: String
    var description: String
    var isPublic: Bool
    var trackCount: Int
    var totalDurationSec: Int
    var coverUrls: [String]
    var ownerId: String
    var ownerName: String
    var createdAt: String
}

struct PlaylistTrack: Codable, Identifiable {
    var position: Int
    var id: String
    var name: String
    var albumId: String
    var albumTitle: String
    var platform: String
    var year: Int
    var durationSec: Int
    var streamUrl: String
    var coverUrl: String?

    var durationFormatted: String {
        let m = durationSec / 60, s = durationSec % 60
        return String(format: "%d:%02d", m, s)
    }

    func asTrack(index: Int) -> Track {
        Track(id: id, index: index, name: name, durationSec: durationSec,
              sizeBytes: 0, streamUrl: streamUrl,
              downloadUrl: streamUrl.replacingOccurrences(of: "/stream", with: "/download"),
              downloaded: false)
    }
}

struct PlaylistDetail: Codable, Identifiable {
    var id: String
    var name: String
    var description: String
    var isPublic: Bool
    var trackCount: Int
    var totalDurationSec: Int
    var coverUrls: [String]
    var ownerId: String
    var ownerName: String
    var createdAt: String
    var updatedAt: String
    var tracks: [PlaylistTrack]

    var totalDurationFormatted: String {
        let h = totalDurationSec / 3600
        let m = (totalDurationSec % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Favorites (local persistence)

struct FavoriteTrack: Codable, Identifiable {
    var id: String        // trackId
    var name: String
    var albumId: String
    var albumTitle: String
    var platform: String
    var year: Int
    var durationSec: Int
    var coverUrl: String?

    var durationFormatted: String {
        let m = durationSec / 60, s = durationSec % 60
        return String(format: "%d:%02d", m, s)
    }
}
