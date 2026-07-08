import SwiftUI

struct Top40View: View {
    @Environment(WishlistStore.self) var wishlist
    @State private var entries: [Top40Entry] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Top 40")
                        .font(VGFont.title())
                        .foregroundStyle(Color.vgText)
                    Text("khinsider weekly chart")
                        .font(VGFont.caption())
                        .foregroundStyle(Color.vgTextMuted)
                }
                .padding(.top, VGSpace.sm)
                .padding(.horizontal, VGSpace.xl)
                .padding(.bottom, VGSpace.md)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let error {
                    Text(error)
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgTextMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            Top40Row(entry: entry)
                        }
                    }
                    .padding(.horizontal, VGSpace.xl)
                }
            }
            .padding(.bottom, VGSpace.xl)
        }
        .background(Color.vgBg)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            entries = try await APIClient.shared.top40()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }
}

private struct Top40Row: View {
    let entry: Top40Entry
    @Environment(WishlistStore.self) var wishlist
    @Environment(LibraryStore.self) var library
    @State private var isHovered = false
    @State private var isOpening = false
    @State private var openError: String?

    private var inWishlist: Bool { wishlist.contains(url: entry.sourceUrl) }

    var body: some View {
        HStack(spacing: VGSpace.md) {
            if isOpening {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 28, alignment: .trailing)
            } else {
                Text(String(entry.rank))
                    .font(VGFont.mono(13))
                    .foregroundStyle(Color.vgTextMuted)
                    .frame(width: 28, alignment: .trailing)
            }

            coverImage

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(VGFont.body())
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
                if let openError {
                    Text(openError)
                        .font(VGFont.caption(10))
                        .foregroundStyle(.red.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if inWishlist {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Color.vgAccent.opacity(0.8))
                    .font(.system(size: 12))
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
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture(count: 2) { Task { await openAlbum() } }
        .contextMenu {
            Button { Task { await openAlbum() } } label: {
                Label("Open Album", systemImage: "play.rectangle")
            }
            if !inWishlist {
                Button { wishlist.add(url: entry.sourceUrl) } label: {
                    Label("Add to Library", systemImage: "plus.circle")
                }
            }
            Divider()
            if let url = URL(string: entry.sourceUrl) {
                Button { NSWorkspace.shared.open(url) } label: {
                    Label("Open on khinsider", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    private func openAlbum() async {
        guard !isOpening else { return }
        isOpening = true
        openError = nil
        do {
            if let summary = try await library.importAlbum(url: entry.sourceUrl) {
                library.pendingNavigation = summary
            } else {
                openError = "Not found after import"
            }
        } catch {
            openError = error.localizedDescription
        }
        isOpening = false
    }

    @ViewBuilder
    private var coverImage: some View {
        if !entry.coverThumbUrl.isEmpty, let url = URL(string: entry.coverThumbUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                default:
                    AlbumLetterArt(title: entry.title, size: 48)
                }
            }
            .frame(width: 48, height: 48)
        } else {
            AlbumLetterArt(title: entry.title, size: 48)
        }
    }
}
