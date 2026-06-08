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
    var coverUrls: [String]

    var covers: [Cover] { coverUrls.map { Cover(url: $0, width: 0, height: 0) } }
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
    var jobId: String
    var albumId: String
    var status: JobStatus
    var error: String?

    enum JobStatus: String, Codable {
        case pending, running, done, failed
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

    var durationFormatted: String {
        let m = durationSec / 60, s = durationSec % 60
        return String(format: "%d:%02d", m, s)
    }
}
