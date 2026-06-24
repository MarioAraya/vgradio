import Foundation
import Observation

struct WishlistItem: Codable, Identifiable {
    var url: String
    var id: String { url }

    var displayTitle: String {
        guard let slug = url.split(separator: "/").last.map(String.init) else { return url }
        return slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}

@Observable
final class WishlistStore {
    private(set) var items: [WishlistItem] = []
    private let key = "vgradio.wishlist"
    private let removedKey = "vgradio.wishlist.removed"
    private var removedURLs: Set<String> = []

    private static let defaultURLs = [
        "https://downloads.khinsider.com/game-soundtracks/album/super-mario-world-snes-gamerip",
        "https://downloads.khinsider.com/game-soundtracks/album/forsaken-roblox-gamerip-2024",
        "https://downloads.khinsider.com/game-soundtracks/album/minecraft",
        "https://downloads.khinsider.com/game-soundtracks/album/cadillacs-dinosaurs-arcade",
        "https://downloads.khinsider.com/game-soundtracks/album/captain-toad-treasure-tracker-original-sound-version",
        "https://downloads.khinsider.com/game-soundtracks/album/kirby-and-the-rainbow-curse",
        "https://downloads.khinsider.com/game-soundtracks/album/super-smash-bros-brawl-gamerip",
        "https://downloads.khinsider.com/game-soundtracks/album/super-mario-galaxy-ost-super-mario-35th-anniversary-release",
        "https://downloads.khinsider.com/game-soundtracks/album/just-shapes-beats-2018",
        "https://downloads.khinsider.com/game-soundtracks/album/super-smash-bros.-anthology-vol.-01-super-smash-bros",
        "https://downloads.khinsider.com/game-soundtracks/album/persona-3-original-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/castlevania-symphony-of-the-night",
        "https://downloads.khinsider.com/game-soundtracks/album/dragon-ball-z-complete-bgm-collection",
        "https://downloads.khinsider.com/game-soundtracks/album/dragon-ball-z-bgm",
        "https://downloads.khinsider.com/game-soundtracks/album/ace-combat-7-skies-unknown-original-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/donkey-kong-country-02-diddys-kong-quest",
        "https://downloads.khinsider.com/game-soundtracks/album/mega-man-x-snes-gamerip",
        "https://downloads.khinsider.com/game-soundtracks/album/fortnite-battle-royale-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/god-of-war-original-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/howls-moving-castle-original-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/super-mario-rpg-original-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/donkey-kong-country-snes",
        "https://downloads.khinsider.com/game-soundtracks/album/bully-original-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/mega-man-x4-psx",
        "https://downloads.khinsider.com/game-soundtracks/album/hotline-miami",
        "https://downloads.khinsider.com/game-soundtracks/album/bowser-s-fury-original-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/megaman-7-original-soundtrack",
        "https://downloads.khinsider.com/game-soundtracks/album/mario-kart-8-deluxe-original-sound-version-switch-wii-u-gamerip-2017",
        "https://downloads.khinsider.com/game-soundtracks/album/super-mario-kart-gamerip",
    ]

    init() {
        loadRemoved()
        load()
        let existing = Set(items.map(\.url))
        let missing = Self.defaultURLs.filter { !existing.contains($0) && !removedURLs.contains($0) }.map { WishlistItem(url: $0) }
        if !missing.isEmpty {
            items.append(contentsOf: missing)
            save()
        }
    }

    func add(url: String) {
        let normalized = url.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, !items.contains(where: { $0.url == normalized }) else { return }
        removedURLs.remove(normalized)
        saveRemoved()
        items.append(WishlistItem(url: normalized))
        save()
    }

    func remove(url: String) {
        items.removeAll(where: { $0.url == url })
        removedURLs.insert(url)
        save()
        saveRemoved()
    }

    func contains(url: String) -> Bool {
        items.contains(where: { $0.url == url })
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              var decoded = try? JSONDecoder().decode([WishlistItem].self, from: data)
        else { return }
        // Fix double-prefix URLs stored by old code (e.g. "https://downloads.khinsider.comhttps://...").
        var needsSave = false
        for i in decoded.indices {
            let fixed = Self.normalizeURL(decoded[i].url)
            if fixed != decoded[i].url {
                decoded[i].url = fixed
                needsSave = true
            }
        }
        items = decoded
        if needsSave { save() }
    }

    private static func normalizeURL(_ url: String) -> String {
        let base = "https://downloads.khinsider.com"
        guard url.hasPrefix(base) else { return url }
        let after = url[base.endIndex...]
        guard !after.hasPrefix("/") else { return url }
        // Double-prefix: find "downloads.khinsider.com" in the suffix and take its path.
        let marker = "downloads.khinsider.com"
        if let markerRange = after.range(of: marker) {
            return base + String(after[markerRange.upperBound...])
        }
        return url
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func loadRemoved() {
        guard let data = UserDefaults.standard.data(forKey: removedKey),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data)
        else { return }
        removedURLs = decoded
    }

    private func saveRemoved() {
        guard let data = try? JSONEncoder().encode(removedURLs) else { return }
        UserDefaults.standard.set(data, forKey: removedKey)
    }
}
