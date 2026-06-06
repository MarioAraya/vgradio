import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem
    @Binding var showAddURL: Bool
    @Environment(LibraryStore.self) var library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar
            Button {
                // ⌘K search handled by SearchOverlay
            } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Color.vgTextMuted)
                    Text("Search")
                        .foregroundStyle(Color.vgTextMuted)
                    Spacer()
                    Text("⌘K")
                        .font(VGFont.caption())
                        .foregroundStyle(Color.vgTextMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.vgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .padding(.horizontal, VGSpace.md)
                .padding(.vertical, VGSpace.sm)
                .background(Color.vgSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .padding(VGSpace.md)

            // MY MUSIC section
            SidebarSection(title: "My Music") {
                SidebarRow(icon: "music.note.list", label: "Library",         item: .library,       selection: $selection)
                SidebarRow(icon: "globe",           label: "Browse",          item: .browse,        selection: $selection)
                SidebarRow(icon: "star",            label: "Favorites",       item: .favorites,     selection: $selection)
                SidebarRow(icon: "clock",           label: "Recently Played", item: .recentlyPlayed, selection: $selection)
            }

            SidebarSection(title: "Quick Actions") {
                Button {
                    showAddURL = true
                } label: {
                    HStack(spacing: VGSpace.sm) {
                        Image(systemName: "plus.circle")
                            .foregroundStyle(Color.vgAccent)
                        Text("Add URL")
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgText)
                    }
                    .padding(.horizontal, VGSpace.md)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Footer
            Divider().overlay(Color.vgSeparator)
            HStack {
                Text("v0.1.0 · \(library.albums.count) albums")
                    .font(VGFont.caption())
                    .foregroundStyle(Color.vgTextMuted)
                Spacer()
            }
            .padding(VGSpace.md)
        }
        .background(Color.vgSidebar)
    }
}

// MARK: - Subviews

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(VGFont.caption(10))
                .foregroundStyle(Color.vgTextMuted)
                .padding(.horizontal, VGSpace.md)
                .padding(.top, VGSpace.md)
                .padding(.bottom, VGSpace.xs)
            content()
        }
    }
}

private struct SidebarRow: View {
    let icon: String
    let label: String
    let item: SidebarItem
    @Binding var selection: SidebarItem

    private var isSelected: Bool { selection == item }

    var body: some View {
        Button { selection = item } label: {
            HStack(spacing: VGSpace.sm) {
                Image(systemName: isSelected ? icon + ".fill" : icon)
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? .white : Color.vgTextSec)
                Text(label)
                    .font(VGFont.body())
                    .foregroundStyle(isSelected ? .white : Color.vgTextSec)
                Spacer()
            }
            .padding(.horizontal, VGSpace.md)
            .padding(.vertical, 7)
            .background(isSelected ? Color.vgAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, VGSpace.sm)
        }
        .buttonStyle(.plain)
    }
}
