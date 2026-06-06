import SwiftUI

@main
struct VGRadioApp: App {
    @State private var library = LibraryStore()
    @State private var favorites = FavoritesStore()
    @State private var player = PlayerService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(favorites)
                .environment(player)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
