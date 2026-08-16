import Foundation

// MARK: - Search helper

/// Token-based match: every whitespace-separated word in `query` must appear
/// somewhere in `haystack`, regardless of order or punctuation between them.
/// e.g. query "rockman forte" matches haystack "Rockman & Forte FC".
func matchesSearchQuery(_ haystack: String, _ query: String) -> Bool {
    let words = query.split(separator: " ").map(String.init)
    guard !words.isEmpty else { return true }
    return words.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
}

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

    var totalDurationSec: Int { tracks.reduce(0) { $0 + $1.durationSec } }

    var totalDurationFormatted: String {
        guard totalDurationSec > 0 else { return "" }
        let h = totalDurationSec / 3600
        let m = (totalDurationSec % 3600) / 60
        let s = totalDurationSec % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

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
    var coverThumbUrl: String = ""
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

    init(id: String, title: String, platform: String, year: Int, albumType: String,
         trackCount: Int, totalDurationSec: Int, coverUrls: [String], coverThumbUrl: String = "") {
        self.id = id
        self.title = title
        self.platform = platform
        self.year = year
        self.albumType = albumType
        self.trackCount = trackCount
        self.totalDurationSec = totalDurationSec
        self.coverUrls = coverUrls
        self.coverThumbUrl = coverThumbUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        platform = try c.decode(String.self, forKey: .platform)
        year = try c.decode(Int.self, forKey: .year)
        albumType = try c.decode(String.self, forKey: .albumType)
        trackCount = try c.decode(Int.self, forKey: .trackCount)
        totalDurationSec = try c.decode(Int.self, forKey: .totalDurationSec)
        coverUrls = try c.decode([String].self, forKey: .coverUrls)
        coverThumbUrl = try c.decodeIfPresent(String.self, forKey: .coverThumbUrl) ?? ""
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
    var pageUrl: String = ""
    var downloaded: Bool = false

    var durationFormatted: String {
        let m = durationSec / 60, s = durationSec % 60
        return String(format: "%d:%02d", m, s)
    }

    init(id: String, index: Int, name: String, durationSec: Int, sizeBytes: Int,
         streamUrl: String, downloadUrl: String, pageUrl: String = "", downloaded: Bool = false) {
        self.id = id
        self.index = index
        self.name = name
        self.durationSec = durationSec
        self.sizeBytes = sizeBytes
        self.streamUrl = streamUrl
        self.downloadUrl = downloadUrl
        self.pageUrl = pageUrl
        self.downloaded = downloaded
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        index = try c.decode(Int.self, forKey: .index)
        name = try c.decode(String.self, forKey: .name)
        durationSec = try c.decode(Int.self, forKey: .durationSec)
        sizeBytes = try c.decode(Int.self, forKey: .sizeBytes)
        streamUrl = try c.decode(String.self, forKey: .streamUrl)
        downloadUrl = try c.decode(String.self, forKey: .downloadUrl)
        pageUrl = try c.decodeIfPresent(String.self, forKey: .pageUrl) ?? ""
        downloaded = try c.decodeIfPresent(Bool.self, forKey: .downloaded) ?? false
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (l: Track, r: Track) -> Bool { l.id == r.id }
}

// MARK: - Connect (remote control across the user's devices)

struct ConnectDevice: Codable, Identifiable, Hashable {
    let id: String
    var name: String
    var type: String        // macos | web | tv
    var isActive: Bool
    var lastSeen: String
}

/// Queue entries carry only IDs; each client hydrates album metadata itself.
struct ConnectQueueEntry: Codable, Hashable {
    var trackId: String
    var albumId: String
}

struct ConnectState: Codable {
    var rev: Int64 = 0
    var deviceId: String = ""
    var isPlaying: Bool = false
    var positionSec: Double = 0
    var updatedAt: String = ""
    var volume: Double = 0.8
    var isMuted: Bool = false
    var isShuffle: Bool = false
    var repeatMode: String = "off"
    var queueIndex: Int = 0
    var coverIndex: Int = 0
    var queue: [ConnectQueueEntry]? = nil
}

/// Every command payload field the hub can carry. All optional: a command uses
/// only the ones it needs, which keeps this a single Codable type instead of an
/// enum with a dozen cases.
struct ConnectPayload: Codable {
    var positionSec: Double?
    var volume: Double?
    var albumId: String?
    var startTrackId: String?
    var trackId: String?
    var index: Int?
    var from: Int?
    var to: Int?
}

struct ConnectCommand: Codable {
    var type: String
    var payload: ConnectPayload?
    var from: String?
}

struct ConnectHello: Codable {
    var deviceId: String
    var activeDeviceId: String
    var state: ConnectState
    var devices: [ConnectDevice]
}

struct ConnectTransfer: Codable {
    var activeDeviceId: String
    var play: Bool
    var state: ConnectState
}

struct Cover: Codable {
    var url: String
    var width: Int
    var height: Int
    var thumbUrl: String = ""

    init(url: String, width: Int, height: Int, thumbUrl: String = "") {
        self.url = url
        self.width = width
        self.height = height
        self.thumbUrl = thumbUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        width = try c.decode(Int.self, forKey: .width)
        height = try c.decode(Int.self, forKey: .height)
        thumbUrl = try c.decodeIfPresent(String.self, forKey: .thumbUrl) ?? ""
    }
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

/// A ranked entry from a platform's "Top 12 [Platform] Albums" box on khinsider.
struct Top12Entry: Decodable, Identifiable {
    var rank: Int
    var title: String
    var sourceUrl: String
    var coverThumbUrl: String
    var id: String { sourceUrl }
}

struct HistoryEntry: Decodable, Identifiable {
    var trackId: String
    var trackName: String
    var albumId: String
    var albumTitle: String
    var platform: String
    var year: Int
    var coverUrl: String
    var playedAt: String
    var id: String { trackId + playedAt }
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

// MARK: - Offline downloads (local persistence)

struct DownloadedTrack: Codable, Identifiable {
    var id: String        // trackId
    var index: Int
    var name: String
    var albumId: String
    var albumTitle: String
    var platform: String
    var year: Int
    var durationSec: Int
    var coverUrl: String?
    /// Filename on disk, e.g. "Album Title - Track Name.mp3". `nil` for
    /// entries saved before this field existed — those fall back to
    /// "<trackId>.mp3" via `resolvedFileName`.
    var fileName: String?

    var resolvedFileName: String { fileName ?? "\(id).mp3" }

    var durationFormatted: String {
        let m = durationSec / 60, s = durationSec % 60
        return String(format: "%d:%02d", m, s)
    }
}
