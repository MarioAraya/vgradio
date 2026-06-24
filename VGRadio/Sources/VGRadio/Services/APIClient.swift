import Foundation

// APIClient talks to the Go backend. Base URL configurable via UserDefaults.
@MainActor
final class APIClient {
    static let shared = APIClient()

    var baseURL: String {
        UserDefaults.standard.string(forKey: "vgradio.backendURL") ?? "http://localhost:8080"
    }

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.httpCookieStorage = HTTPCookieStorage.shared
        cfg.httpShouldSetCookies = true
        cfg.httpCookieAcceptPolicy = .always
        return URLSession(configuration: cfg)
    }()

    private func url(_ path: String) throws -> URL {
        guard let u = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }
        return u
    }

    // MARK: - Albums

    func albums() async throws -> [AlbumSummary] {
        let (data, _) = try await session.data(from: try url("/albums"))
        return try JSONDecoder().decode([AlbumSummary].self, from: data)
    }

    func album(_ id: String) async throws -> Album {
        let (data, _) = try await session.data(from: try url("/albums/\(id)"))
        return try JSONDecoder().decode(Album.self, from: data)
    }

    @discardableResult
    func addAlbum(url albumURL: String) async throws -> ScrapeJob {
        var req = URLRequest(url: try url("/albums"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["url": albumURL])
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 422 {
            let err = try? JSONDecoder().decode([String: String].self, from: data)
            throw VGError.ssrf(err?["error"] ?? "URL not allowed")
        }
        return try JSONDecoder().decode(ScrapeJob.self, from: data)
    }

    // MARK: - Jobs

    func job(_ id: String) async throws -> ScrapeJob {
        let (data, _) = try await session.data(from: try url("/jobs/\(id)"))
        return try JSONDecoder().decode(ScrapeJob.self, from: data)
    }

    // MARK: - Track fetch (download to server local disk)

    func fetchTrack(_ trackID: String) async throws {
        var req = URLRequest(url: try url("/tracks/\(trackID)/fetch"))
        req.httpMethod = "POST"
        req.timeoutInterval = 180  // large MP3s can take a while
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw VGError.jobFailed("fetch failed (\(http.statusCode))")
        }
    }

    // MARK: - Catalog

    func startCatalogSync(letter: String = "") async throws {
        var comps = URLComponents(string: baseURL + "/catalog/sync")!
        if !letter.isEmpty { comps.queryItems = [.init(name: "letter", value: letter)] }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 && http.statusCode != 409 {
            throw VGError.jobFailed("sync failed (\(http.statusCode))")
        }
    }

    func catalogSyncProgress() async throws -> CatalogSyncProgress {
        let (data, _) = try await session.data(from: try url("/catalog/sync"))
        return try JSONDecoder().decode(CatalogSyncProgress.self, from: data)
    }

    func catalog(q: String = "", platform: String = "", letter: String = "", offset: Int = 0, limit: Int = 50) async throws -> CatalogPage {
        var comps = URLComponents(string: baseURL + "/catalog")!
        comps.queryItems = [
            .init(name: "q", value: q),
            .init(name: "platform", value: platform),
            .init(name: "letter", value: letter),
            .init(name: "offset", value: String(offset)),
            .init(name: "limit", value: String(limit)),
        ].filter { !($0.value ?? "").isEmpty || $0.name == "offset" }
        let (data, _) = try await session.data(from: comps.url!)
        return try JSONDecoder().decode(CatalogPage.self, from: data)
    }

    func catalogConsoles() async throws -> [CatalogConsole] {
        let (data, _) = try await session.data(from: try url("/catalog/consoles"))
        return try JSONDecoder().decode([CatalogConsole].self, from: data)
    }

    // MARK: - Stream URL

    func streamURL(for track: Track) -> URL? {
        URL(string: baseURL + track.streamUrl)
    }

    // MARK: - Auth

    func me() async throws -> UserProfile? {
        let (data, resp) = try await session.data(from: try url("/auth/me"))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(UserProfile.self, from: data)
    }

    func login(email: String, password: String) async throws -> UserProfile {
        var req = URLRequest(url: try url("/auth/login"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Login failed"
            throw VGError.jobFailed(msg)
        }
        return try JSONDecoder().decode(UserProfile.self, from: data)
    }

    func logout() async throws {
        var req = URLRequest(url: try url("/auth/logout"))
        req.httpMethod = "POST"
        _ = try await session.data(for: req)
    }

    // MARK: - Track Favorites

    func favoriteTracks() async throws -> [FavoriteTrack] {
        let (data, resp) = try await session.data(from: try url("/favorites/tracks"))
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        return try JSONDecoder().decode([FavoriteTrack].self, from: data)
    }

    @discardableResult
    func toggleTrackFavorite(id trackID: String) async throws -> Bool {
        var req = URLRequest(url: try url("/favorites/tracks/\(trackID)"))
        req.httpMethod = "POST"
        let (data, _) = try await session.data(for: req)
        let result = try JSONDecoder().decode([String: Bool].self, from: data)
        return result["favorited"] ?? false
    }

    // MARK: - Playlists

    func playlists() async throws -> [PlaylistSummary] {
        let (data, _) = try await session.data(from: try url("/playlists"))
        return try JSONDecoder().decode([PlaylistSummary].self, from: data)
    }

    func playlist(id: String) async throws -> PlaylistDetail {
        let (data, _) = try await session.data(from: try url("/playlists/\(id)"))
        return try JSONDecoder().decode(PlaylistDetail.self, from: data)
    }

    func createPlaylist(name: String, description: String = "", isPublic: Bool = false) async throws -> PlaylistSummary {
        var req = URLRequest(url: try url("/playlists"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name, "description": description, "isPublic": isPublic
        ])
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? "Error"
            throw VGError.jobFailed(msg)
        }
        return try JSONDecoder().decode(PlaylistSummary.self, from: data)
    }

    func updatePlaylist(id: String, name: String, description: String, isPublic: Bool) async throws {
        var req = URLRequest(url: try url("/playlists/\(id)"))
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name, "description": description, "isPublic": isPublic
        ])
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw VGError.jobFailed("Update failed (\(http.statusCode))")
        }
    }

    func deletePlaylist(id: String) async throws {
        var req = URLRequest(url: try url("/playlists/\(id)"))
        req.httpMethod = "DELETE"
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw VGError.jobFailed("Delete failed (\(http.statusCode))")
        }
    }

    func addTrackToPlaylist(playlistId: String, trackId: String) async throws {
        var req = URLRequest(url: try url("/playlists/\(playlistId)/tracks"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["trackId": trackId])
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 && http.statusCode != 409 {
            throw VGError.jobFailed("Add track failed (\(http.statusCode))")
        }
    }

    func removeTrackFromPlaylist(playlistId: String, trackId: String) async throws {
        var req = URLRequest(url: try url("/playlists/\(playlistId)/tracks/\(trackId)"))
        req.httpMethod = "DELETE"
        let (_, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
            throw VGError.jobFailed("Remove track failed (\(http.statusCode))")
        }
    }
}

enum VGError: LocalizedError {
    case ssrf(String)
    case jobFailed(String)

    var errorDescription: String? {
        switch self {
        case .ssrf(let msg): return "URL not allowed: \(msg)"
        case .jobFailed(let msg): return "Scrape failed: \(msg)"
        }
    }
}
