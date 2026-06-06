import Foundation

final class CoverPrefsStore {
    static let shared = CoverPrefsStore()
    private let key = "vgradio.coverIndex"
    private var prefs: [String: Int] = [:]

    private init() { load() }

    func index(for albumID: String) -> Int { prefs[albumID] ?? 0 }

    func set(_ idx: Int, for albumID: String) {
        if idx == 0 { prefs.removeValue(forKey: albumID) }
        else { prefs[albumID] = idx }
        save()
    }

    private func load() {
        prefs = (UserDefaults.standard.dictionary(forKey: key) as? [String: Int]) ?? [:]
    }

    private func save() {
        UserDefaults.standard.set(prefs, forKey: key)
    }
}
