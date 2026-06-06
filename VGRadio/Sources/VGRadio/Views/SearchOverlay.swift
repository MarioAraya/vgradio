import SwiftUI

struct SearchOverlay: View {
    @Binding var isShowing: Bool
    @Environment(LibraryStore.self) var library
    @State private var query = ""

    private var results: [AlbumSummary] {
        guard !query.isEmpty else { return [] }
        return library.albums.filter {
            $0.title.localizedCaseInsensitiveContains(query) ||
            $0.platform.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { isShowing = false }

            VStack(spacing: 0) {
                // Search input
                HStack(spacing: VGSpace.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.vgTextSec)
                    TextField("Search albums, tracks, platforms...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .foregroundStyle(Color.vgText)
                }
                .padding(VGSpace.md)

                if results.isEmpty && query.isEmpty {
                    HStack(spacing: VGSpace.md) {
                        Text("Type to search").font(VGFont.caption())
                        Text("·").font(VGFont.caption())
                        HStack(spacing: 4) {
                            KBDKey("↩")
                            Text("to open").font(VGFont.caption())
                        }
                        Text("·").font(VGFont.caption())
                        HStack(spacing: 4) {
                            KBDKey("esc")
                            Text("to close").font(VGFont.caption())
                        }
                    }
                    .foregroundStyle(Color.vgTextMuted)
                    .padding(.horizontal, VGSpace.md)
                    .padding(.bottom, VGSpace.md)
                } else if !results.isEmpty {
                    Divider().overlay(Color.vgSeparator)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { album in
                                SearchResultRow(album: album) { isShowing = false }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                }
            }
            .background(Color.vgSidebar.opacity(0.95))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.vgSeparator, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: 30)
            .frame(width: 560)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 120)
        }
        .onKeyPress(.escape) { isShowing = false; return .handled }
    }
}

private struct SearchResultRow: View {
    let album: AlbumSummary
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: VGSpace.md) {
            AlbumLetterArt(title: album.title, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(VGFont.body()).foregroundStyle(Color.vgText)
                Text("\(album.platform) · \(album.year)").font(VGFont.caption()).foregroundStyle(Color.vgTextSec)
            }
            Spacer()
            Text("\(album.trackCount) tracks").font(VGFont.caption()).foregroundStyle(Color.vgTextMuted)
        }
        .padding(.horizontal, VGSpace.md)
        .padding(.vertical, VGSpace.sm)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}

private struct KBDKey: View {
    let label: String
    init(_ label: String) { self.label = label }
    var body: some View {
        Text(label)
            .font(VGFont.caption())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.vgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.vgSeparator))
    }
}
