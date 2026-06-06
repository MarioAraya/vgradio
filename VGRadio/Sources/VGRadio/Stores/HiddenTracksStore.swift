import Foundation
import Observation

@Observable
final class HiddenTracksStore {
    private(set) var hiddenIDs: Set<String> = []
    private let key = "vgradio.hiddenTracks"

    init() { load() }

    func isHidden(_ id: String) -> Bool { hiddenIDs.contains(id) }

    func toggle(_ id: String) {
        if hiddenIDs.contains(id) { hiddenIDs.remove(id) }
        else { hiddenIDs.insert(id) }
        save()
    }

    private func load() {
        let arr = UserDefaults.standard.array(forKey: key) as? [String] ?? []
        hiddenIDs = Set(arr)
    }

    private func save() {
        UserDefaults.standard.set(Array(hiddenIDs), forKey: key)
    }
}
