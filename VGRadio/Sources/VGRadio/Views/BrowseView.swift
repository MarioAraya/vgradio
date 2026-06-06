import SwiftUI

// Fase 1.5 — placeholder hasta que el catálogo esté implementado en el backend.
struct BrowseView: View {
    var body: some View {
        VStack(spacing: VGSpace.md) {
            Image(systemName: "globe")
                .font(.system(size: 40))
                .foregroundStyle(Color.vgTextMuted)
            Text("Browse Catalog")
                .font(VGFont.heading())
                .foregroundStyle(Color.vgTextSec)
            Text("Coming in fase 1.5 — full catalog search by platform, letter, and title.")
                .font(VGFont.body())
                .foregroundStyle(Color.vgTextMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vgBg)
    }
}

struct RecentlyPlayedView: View {
    var body: some View {
        VStack(spacing: VGSpace.md) {
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundStyle(Color.vgTextMuted)
            Text("Recently Played")
                .font(VGFont.heading())
                .foregroundStyle(Color.vgTextSec)
            Text("Tracks you've played will appear here.")
                .font(VGFont.body())
                .foregroundStyle(Color.vgTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vgBg)
    }
}
