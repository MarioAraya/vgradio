import SwiftUI

struct SearchOverlay: View {
    @Binding var isShowing: Bool
    @Environment(LibraryStore.self) var library
    @State private var query = ""
    @FocusState private var isFocused: Bool
    @State private var catalogResults: [CatalogEntry] = []
    @State private var catalogSearchTask: Task<Void, Never>?

    private var results: [AlbumSummary] {
        guard !query.isEmpty else { return [] }
        return library.albums.filter {
            matchesSearchQuery($0.title, query) || matchesSearchQuery($0.platform, query)
        }
    }

    /// Catalog (not-yet-imported) matches, minus anything already shown from the library.
    private var extraCatalogResults: [CatalogEntry] {
        let libraryTitles = Set(results.map { $0.title.lowercased() })
        return catalogResults.filter { !libraryTitles.contains($0.title.lowercased()) }
    }

    private func scheduleCatalogSearch() {
        catalogSearchTask?.cancel()
        guard !query.isEmpty else { catalogResults = []; return }
        let q = query
        catalogSearchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            guard let page = try? await APIClient.shared.catalog(q: q, limit: 8) else { return }
            guard !Task.isCancelled, q == query else { return }
            catalogResults = page.items
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
                        .focused($isFocused)
                        .onChange(of: query) { _, _ in scheduleCatalogSearch() }
                }
                .padding(VGSpace.md)

                if results.isEmpty && extraCatalogResults.isEmpty && query.isEmpty {
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
                } else if !results.isEmpty || !extraCatalogResults.isEmpty {
                    Divider().overlay(Color.vgSeparator)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(results) { album in
                                SearchResultRow(album: album) {
                                    library.pendingNavigation = album
                                    isShowing = false
                                }
                            }
                            if !extraCatalogResults.isEmpty {
                                if !results.isEmpty {
                                    Text("FROM KHINSIDER")
                                        .font(VGFont.label(10))
                                        .tracking(1.2)
                                        .foregroundStyle(Color.vgTextMuted)
                                        .padding(.horizontal, VGSpace.md)
                                        .padding(.top, VGSpace.sm)
                                        .padding(.bottom, 4)
                                }
                                ForEach(extraCatalogResults) { entry in
                                    CatalogSearchResultRow(entry: entry, onOpened: { isShowing = false })
                                }
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
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { isFocused = true }
        }
    }
}

private struct SearchResultRow: View {
    let album: AlbumSummary
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: VGSpace.md) {
            if !album.coverThumbUrl.isEmpty, let url = AlbumCoverView.resolveURL(album.coverThumbUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                    default: AlbumLetterArt(title: album.title, size: 36)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                AlbumLetterArt(title: album.title, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title).font(VGFont.body()).foregroundStyle(Color.vgText)
                Text("\(album.platform) · \(String(album.year))").font(VGFont.caption()).foregroundStyle(Color.vgTextSec)
            }
            Spacer()
            Text("\(album.trackCount) tracks").font(VGFont.caption()).foregroundStyle(Color.vgTextMuted)
        }
        .padding(.horizontal, VGSpace.md)
        .padding(.vertical, VGSpace.sm)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
    }
}

private struct CatalogSearchResultRow: View {
    let entry: CatalogEntry
    let onOpened: () -> Void
    @Environment(LibraryStore.self) var library
    @State private var isHovered = false
    @State private var isOpening = false
    @State private var openError: String?

    var body: some View {
        HStack(spacing: VGSpace.md) {
            if isOpening {
                ProgressView().scaleEffect(0.6).frame(width: 36, height: 36)
            } else {
                AlbumLetterArt(title: entry.title, size: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title).font(VGFont.body()).foregroundStyle(Color.vgText)
                if let openError {
                    Text(openError).font(VGFont.caption(10)).foregroundStyle(.red.opacity(0.85))
                } else {
                    Text("\(entry.platform) · \(entry.year > 0 ? String(entry.year) : "—")")
                        .font(VGFont.caption()).foregroundStyle(Color.vgTextSec)
                }
            }
            Spacer()
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 13))
                .foregroundStyle(Color.vgTextMuted)
        }
        .padding(.horizontal, VGSpace.md)
        .padding(.vertical, VGSpace.sm)
        .background(isHovered ? Color.vgSurfaceHi : Color.clear)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { Task { await open() } }
    }

    private func open() async {
        guard !isOpening else { return }
        isOpening = true
        openError = nil
        do {
            if let summary = try await library.importAlbum(url: entry.sourceUrl) {
                library.pendingNavigation = summary
                onOpened()
            } else {
                openError = "Not found after import"
                isOpening = false
            }
        } catch {
            openError = error.localizedDescription
            isOpening = false
        }
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
