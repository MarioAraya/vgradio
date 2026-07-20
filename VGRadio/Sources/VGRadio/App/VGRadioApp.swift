import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        // AppKit's default tooltip delay is ~1.5s; this app-scoped default cuts it to 0.5s.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 500])
    }
}

@main
struct VGRadioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var library = LibraryStore()
    @State private var favorites = FavoritesStore()
    @State private var player = PlayerService()
    @State private var hidden = HiddenTracksStore()
    @State private var auth = AuthStore()
    @State private var playlistsStore = PlaylistsStore()
    @State private var offline = OfflineStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(favorites)
                .environment(player)
                .environment(hidden)
                .environment(auth)
                .environment(playlistsStore)
                .environment(offline)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    player.hiddenTracks = hidden
                    player.offline = offline
                    offline.startMonitoring()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
