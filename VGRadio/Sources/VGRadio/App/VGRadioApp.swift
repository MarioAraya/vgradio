import SwiftUI

@main
struct VGRadioApp: App {
    @State private var library = LibraryStore()
    @State private var favorites = FavoritesStore()
    @State private var player = PlayerService()
    @State private var hidden = HiddenTracksStore()
    @State private var wishlist = WishlistStore()
    @State private var auth = AuthStore()
    @State private var playlistsStore = PlaylistsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(favorites)
                .environment(player)
                .environment(hidden)
                .environment(wishlist)
                .environment(auth)
                .environment(playlistsStore)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear { player.hiddenTracks = hidden }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
