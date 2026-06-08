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
                try await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            }
        }
    }
}
