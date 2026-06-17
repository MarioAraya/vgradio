import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem
    @Binding var showAddURL: Bool
    @Environment(LibraryStore.self) var library

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar — h-7 = 28px, text 12px
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.vgTextMuted)
                Text("Search")
                    .font(VGFont.caption(12))
                    .foregroundStyle(Color.vgTextMuted)
                Spacer()
                Text("⌘K")
                    .font(VGFont.label(10))
                    .foregroundStyle(Color.vgTextMuted)
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.05)))
            .padding(.horizontal, 12)
            .padding(.top, 36)
            .padding(.bottom, 4)

            // MY MUSIC
            SidebarSection(title: "My Music") {
                SidebarRow(icon: "music.note.list", label: "Library",         item: .library,       selection: $selection)
                SidebarRow(icon: "globe",           label: "Browse",          item: .browse,        selection: $selection)
                SidebarRow(icon: "star",            label: "Favorites",       item: .favorites,     selection: $selection)
                SidebarRow(icon: "clock",           label: "Recently Played", item: .recentlyPlayed, selection: $selection)
            }

            SidebarSection(title: "Quick Actions") {
                // Add URL styled the same as nav rows
                Button { showAddURL = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.vgAccent)
                            .frame(width: 16)
                        Text("Add URL")
                            .font(VGFont.caption(13))
                            .foregroundStyle(Color.vgText)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }

            Spacer()

            Divider().overlay(Color.vgSeparator)
            HStack {
                Text("v0.1.0 · \(library.albums.count) albums")
                    .font(VGFont.label(10))
                    .foregroundStyle(Color.vgTextMuted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity)
        .background(Color.vgSidebar)
        .ignoresSafeArea(.all, edges: .top)
    }
}

// MARK: - Subviews

private struct SidebarSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(VGFont.label(10))
                .tracking(1.2)
                .foregroundStyle(Color.vgTextMuted)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 4)
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
            ZStack(alignment: .leading) {
                // Active indicator: 2px left line
                if isSelected {
                    Color.vgAccent
                        .frame(width: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 1))
                        .padding(.vertical, 6)
                        .frame(maxHeight: .infinity, alignment: .leading)
                }

                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 13))
                        .frame(width: 16)
                        .foregroundStyle(isSelected ? Color.vgAccent : Color.vgTextSec)
                    Text(label)
                        .font(VGFont.caption(13))
                        .foregroundStyle(isSelected ? Color.vgAccent : Color.vgTextSec)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.leading, 2) // make room for indicator line
            }
            .frame(height: 28)
            .background(isSelected ? Color.vgAccentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}
