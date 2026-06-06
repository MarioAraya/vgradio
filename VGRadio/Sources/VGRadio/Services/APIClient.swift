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

    // MARK: - Stream URL

    func streamURL(for track: Track) -> URL? {
        URL(string: baseURL + track.streamUrl)
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
