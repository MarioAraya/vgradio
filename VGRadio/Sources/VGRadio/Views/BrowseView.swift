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
            Button(action: { Task { await catalog.startSync() } }) {
                HStack(spacing: 4) {
                    Image(systemName: catalog.isSyncing ? "arrow.triangle.2.circlepath" : "arrow.down.circle")
                    Text(catalog.isSyncing ? "Syncing…" : "Sync Catalog")
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
                    .listRowInsets(.init(top: 1, leading: VGSpace.md, bottom: 1, trailing: VGSpace.md))
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
                    ? "Press Sync Catalog to fetch all albums from khinsider."
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
    @State private var isHovered = false
    @State private var isImporting = false
    @State private var imported = false

    var body: some View {
        HStack(spacing: VGSpace.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(VGFont.body())
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
                HStack(spacing: VGSpace.xs) {
                    if !entry.platform.isEmpty {
                        Text(entry.platform)
                            .font(VGFont.caption())
                            .foregroundStyle(Color.vgTextMuted)
                    }
                    if entry.year > 0 {
                        Text("·")
                            .font(VGFont.caption())
                            .foregroundStyle(Color.vgTextMuted)
                        Text(String(entry.year))
                            .font(VGFont.caption())
                            .foregroundStyle(Color.vgTextMuted)
                    }
                }
            }
            Spacer()
            importBadge
        }
        .frame(height: 40)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var importBadge: some View {
        if imported {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green.opacity(0.8))
                .font(.system(size: 14))
        } else if isImporting {
            ProgressView().controlSize(.small)
        } else if isHovered {
            Button(action: importAlbum) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.vgAccent)
            }
            .buttonStyle(.plain)
            .help("Import album to library")
        }
    }

    private func importAlbum() {
        isImporting = true
        Task {
            do {
                let fullURL = "https://downloads.khinsider.com" + entry.sourceUrl
                try await APIClient.shared.addAlbum(url: fullURL)
                imported = true
            } catch {}
            isImporting = false
        }
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
