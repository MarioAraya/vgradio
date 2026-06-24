import SwiftUI

private let allLetters: [String] = [""] + ["0-9"] + (65...90).map { String(UnicodeScalar($0)!) }

struct BrowseView: View {
    @State private var catalog = CatalogStore()
    @State private var searchText = ""
    @Environment(LibraryStore.self) var library

    var body: some View {
        VStack(spacing: 0) {
            toolbarRow
            Divider().background(Color.white.opacity(0.06))
            if catalog.entries.isEmpty && !catalog.isLoading {
                emptyState
            } else {
                resultsList
            }
        }
        .background(Color.vgBg)
        .task {
            await catalog.refreshSyncStatus()
            await catalog.loadConsoles()
            catalog.reload()
        }
        .onChange(of: searchText) { _, v in catalog.searchQuery = v }
    }

    // MARK: - Toolbar

    private var toolbarRow: some View {
        VStack(spacing: VGSpace.sm) {
            HStack(spacing: VGSpace.sm) {
                HStack(spacing: VGSpace.xs) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.vgTextMuted)
                    TextField("Search albums…", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(VGFont.body())
                }
                .padding(.horizontal, VGSpace.sm)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .frame(maxWidth: 280)

                Spacer()
                syncSection
            }

            letterStrip

            if !catalog.consoles.isEmpty {
                consolePicker
            }
        }
        .padding(.horizontal, VGSpace.md)
        .padding(.vertical, VGSpace.sm)
    }

    private var syncButtonLabel: String {
        let l = catalog.selectedLetter
        if l.isEmpty { return "Sync All" }
        return "Sync \(l)"
    }

    private var syncSection: some View {
        HStack(spacing: VGSpace.sm) {
            if let p = catalog.syncProgress {
                if catalog.isSyncing {
                    ProgressView().controlSize(.small)
                    Text("\(p.done)/\(p.total) pages · \(p.entries) entries")
                        .font(VGFont.caption())
                        .foregroundStyle(Color.vgTextMuted)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green.opacity(0.8))
                        .font(.system(size: 13))
                    Text("\(p.entries) albums · \(p.consoles) consoles")
                        .font(VGFont.caption())
                        .foregroundStyle(Color.vgTextMuted)
                }
            }
            Button(action: { Task { await catalog.startSync(letter: catalog.selectedLetter) } }) {
                HStack(spacing: 4) {
                    Image(systemName: catalog.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                    Text(catalog.isSyncing ? "Syncing…" : syncButtonLabel)
                }
                .font(VGFont.caption())
                .foregroundStyle(catalog.isSyncing ? Color.vgTextMuted : Color.vgAccent)
            }
            .buttonStyle(.plain)
            .disabled(catalog.isSyncing)
        }
    }

    private var letterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(allLetters, id: \.self) { letter in
                    let sel = catalog.selectedLetter == letter
                    Button(letter.isEmpty ? "All" : letter) {
                        catalog.selectedLetter = letter
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: sel ? .semibold : .regular))
                    .foregroundStyle(sel ? Color.vgAccent : Color.vgTextSec)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(sel ? Color.vgAccentSoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
        }
    }

    private var consolePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                consoleChip(id: "", name: "All")
                ForEach(catalog.consoles) { c in
                    consoleChip(id: c.name, name: "\(c.name) (\(c.albumCount))")
                }
            }
        }
    }

    private func consoleChip(id: String, name: String) -> some View {
        let sel = catalog.selectedConsole == id
        return Button(name) {
            catalog.selectedConsole = id
        }
        .buttonStyle(.plain)
        .font(.system(size: 11, weight: sel ? .semibold : .regular))
        .foregroundStyle(sel ? Color.vgAccent : Color.vgTextSec)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(sel ? Color.vgAccentSoft : Color.white.opacity(0.04))
        .clipShape(Capsule())
    }

    // MARK: - Results

    private var resultsList: some View {
        List {
            ForEach(catalog.entries) { entry in
                CatalogEntryRow(entry: entry)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(.init(top: 2, leading: VGSpace.md, bottom: 2, trailing: VGSpace.md))
                    .onAppear {
                        if entry.id == catalog.entries.last?.id {
                            catalog.loadMore()
                        }
                    }
            }
            if catalog.isLoading {
                HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if catalog.hasMore && !catalog.isLoading {
                Button("Load more") { catalog.loadMore() }
                    .buttonStyle(.plain)
                    .font(VGFont.caption())
                    .foregroundStyle(Color.vgAccent)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .overlay(alignment: .top) {
            if let err = catalog.error {
                Text(err)
                    .font(VGFont.caption())
                    .foregroundStyle(.red.opacity(0.8))
                    .padding(VGSpace.sm)
                    .background(Color.vgSidebar)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.top, VGSpace.sm)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: VGSpace.md) {
            if catalog.isLoading {
                ProgressView().controlSize(.regular)
                Text("Loading…")
                    .font(VGFont.body())
                    .foregroundStyle(Color.vgTextMuted)
            } else {
                Image(systemName: "archivebox")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.vgTextMuted)
                Text(searchText.isEmpty ? "Catalog empty" : "No results")
                    .font(VGFont.heading())
                    .foregroundStyle(Color.vgTextSec)
                Text(searchText.isEmpty
                    ? "Select a letter and press Sync to fetch albums from khinsider."
                    : "Try a different search term or filter.")
                    .font(VGFont.body())
                    .foregroundStyle(Color.vgTextMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Row

private struct CatalogEntryRow: View {
    let entry: CatalogEntry
    @Environment(WishlistStore.self) var wishlist
    @State private var isHovered = false

    private var inWishlist: Bool { wishlist.contains(url: entry.sourceUrl) }

    var body: some View {
        HStack(spacing: 0) {
            // Col 1: Add / saved indicator (44px)
            addButton
                .frame(width: 44)

            // Col 2: Cover thumbnail (44x44)
            coverImage
                .padding(.trailing, VGSpace.sm)

            // Col 3: Title (flexible)
            Text(entry.title)
                .font(VGFont.body())
                .foregroundStyle(Color.vgText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Col 4: Platform (~90px)
            Text(entry.platform)
                .font(VGFont.caption(11))
                .foregroundStyle(Color.vgTextMuted)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            // Col 5: Type (~80px)
            Text(entry.albumType)
                .font(VGFont.caption(11))
                .foregroundStyle(Color.vgTextMuted)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)

            // Col 6: Year (45px)
            Text(entry.year > 0 ? String(entry.year) : "")
                .font(VGFont.caption(11))
                .foregroundStyle(Color.vgTextMuted)
                .frame(width: 45, alignment: .trailing)
        }
        .frame(height: 52)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var addButton: some View {
        if inWishlist {
            Image(systemName: "bookmark.fill")
                .foregroundStyle(Color.vgAccent.opacity(0.8))
                .font(.system(size: 12))
                .frame(width: 44)
        } else if isHovered {
            Button(action: { wishlist.add(url: entry.sourceUrl) }) {
                Text("Add")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.vgAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.vgAccentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .help("Add to Library")
        } else {
            Color.clear.frame(width: 44)
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let urlStr = entry.thumbnailURL, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                default:
                    placeholderCover
                }
            }
        } else {
            placeholderCover
        }
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.white.opacity(0.04))
            .frame(width: 44, height: 44)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.vgTextMuted)
            )
    }
}

// MARK: - Recently Played stub

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
