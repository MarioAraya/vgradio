import Foundation

/// Drag payload for "drag album/track onto a playlist" — carries either
/// explicit track IDs (single track drag) or an albumId (whole-album drag,
/// resolved to track IDs by the drop target since AlbumSummary has no tracks).
///
/// Uses NSItemProvider + onDrag/onDrop instead of Transferable/.draggable —
/// the new Transferable API fails to even start a drag session on macOS in
/// this app's view hierarchy (grid cells with simultaneous tap gestures).
struct PlaylistDragItem: Codable {
    var trackIds: [String] = []
    var albumId: String? = nil

    static let typeIdentifier = "com.vgradio.playlist-item"

    func makeItemProvider() -> NSItemProvider {
        let data = try? JSONEncoder().encode(self)
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: Self.typeIdentifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    static func from(_ provider: NSItemProvider, completion: @escaping (PlaylistDragItem?) -> Void) {
        guard provider.hasItemConformingToTypeIdentifier(typeIdentifier) else {
            completion(nil)
            return
        }
        provider.loadDataRepresentation(forTypeIdentifier: typeIdentifier) { data, _ in
            guard let data, let item = try? JSONDecoder().decode(PlaylistDragItem.self, from: data) else {
                completion(nil)
                return
            }
            completion(item)
        }
    }
}
