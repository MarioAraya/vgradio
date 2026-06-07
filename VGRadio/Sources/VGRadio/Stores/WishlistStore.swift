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
        load()
        let existing = Set(items.map(\.url))
        let missing = Self.defaultURLs.filter { !existing.contains($0) }.map { WishlistItem(url: $0) }
        if !missing.isEmpty {
            items.append(contentsOf: missing)
            save()
        }
    }

    func add(url: String) {
        let normalized = url.trimmingCharacters(in: .whitespaces)
        guard !normalized.isEmpty, !items.contains(where: { $0.url == normalized }) else { return }
        items.append(WishlistItem(url: normalized))
        save()
    }

    func remove(url: String) {
        items.removeAll(where: { $0.url == url })
        save()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([WishlistItem].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
