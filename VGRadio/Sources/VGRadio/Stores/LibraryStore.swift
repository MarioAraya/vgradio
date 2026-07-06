import Observation

@Observable
final class LibraryStore {
    private(set) var albums: [AlbumSummary] = []
    private(set) var isLoading = false
    private(set) var error: String?
    var pendingNavigation: AlbumSummary? = nil

    func load() async {
        isLoading = true
        error = nil
        do {
            albums = try await APIClient.shared.albums()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func addAlbum(url: String) async throws -> ScrapeJob {
        let job = try await APIClient.shared.addAlbum(url: url)
        return job
    }

    func pollJob(_ jobID: String) async throws -> ScrapeJob {
        while true {
            let job = try await APIClient.shared.job(jobID)
            switch job.status {
            case .done:
                await load()
                return job
            case .failed:
                throw VGError.jobFailed(job.error ?? "unknown error")
            case .pending, .running:
                try await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    /// Imports (or reuses, if already scraped) the album at `url` and returns its summary
    /// once available in `albums`, so callers can navigate straight to it.
    @discardableResult
    func importAlbum(url: String) async throws -> AlbumSummary? {
        let job = try await addAlbum(url: url)
        if let jobId = job.jobId {
            _ = try await pollJob(jobId)
        } else {
            // album already in DB (POST returned 200 with status: "done", no jobId)
            await load()
        }
        return albums.first { $0.id == job.albumId }
    }

    func deleteAlbum(_ id: String) async throws {
        try await APIClient.shared.deleteAlbum(id)
        albums.removeAll { $0.id == id }
    }
}
