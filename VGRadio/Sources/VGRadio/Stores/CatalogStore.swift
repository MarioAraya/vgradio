import SwiftUI

@Observable
@MainActor
final class CatalogStore {
    private let api = APIClient.shared

    var entries: [CatalogEntry] = []
    var consoles: [CatalogConsole] = []
    var total: Int = 0
    var isLoading = false
    var isSyncing = false
    var syncProgress: CatalogSyncProgress? = nil
    var error: String? = nil

    var searchQuery = "" {
        didSet { if oldValue != searchQuery { scheduleSearch() } }
    }
    var selectedLetter = "" {
        didSet { if oldValue != selectedLetter { reload() } }
    }
    var selectedConsole = "" {
        didSet { if oldValue != selectedConsole { reload() } }
    }

    private let limit = 50
    private var offset = 0
    var hasMore: Bool { entries.count < total }

    private var searchTask: Task<Void, Never>? = nil
    private var syncPollTask: Task<Void, Never>? = nil

    func reload() {
        offset = 0
        entries = []
        total = 0
        Task { await fetch() }
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            reload()
        }
    }

    func loadMore() {
        guard hasMore && !isLoading else { return }
        Task { await fetch() }
    }

    private func fetch() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let page = try await api.catalog(
                q: searchQuery,
                platform: selectedConsole,
                letter: selectedLetter,
                offset: offset,
                limit: limit
            )
            total = page.total
            entries.append(contentsOf: page.items)
            offset += page.items.count
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadConsoles() async {
        do {
            consoles = try await api.catalogConsoles()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func startSync(letter: String = "") async {
        guard !isSyncing else { return }
        isSyncing = true
        error = nil
        do {
            try await api.startCatalogSync(letter: letter)
        } catch {
            self.error = error.localizedDescription
            isSyncing = false
            return
        }
        syncPollTask?.cancel()
        syncPollTask = Task { await pollSync() }
    }

    private func pollSync() async {
        while !Task.isCancelled {
            do {
                let progress = try await api.catalogSyncProgress()
                syncProgress = progress
                if !progress.running {
                    isSyncing = false
                    reload()
                    await loadConsoles()
                    return
                }
            } catch {
                self.error = error.localizedDescription
                isSyncing = false
                return
            }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }

    func refreshSyncStatus() async {
        do {
            let progress = try await api.catalogSyncProgress()
            syncProgress = progress
            isSyncing = progress.running
            if progress.running {
                syncPollTask?.cancel()
                syncPollTask = Task { await pollSync() }
            }
        } catch {}
    }
}
