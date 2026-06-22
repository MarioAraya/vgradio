import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarItem
    @Binding var showAddURL: Bool
    @Environment(LibraryStore.self) var library
    @Environment(AuthStore.self) var auth
    @Environment(PlaylistsStore.self) var playlists

    @State private var showLogin = false
    @State private var showNewPlaylist = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Search bar
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
                SidebarRow(icon: "music.note.list", label: "Library",         item: .library,        selection: $selection)
                SidebarRow(icon: "globe",           label: "Browse",          item: .browse,         selection: $selection)
                SidebarRow(icon: "star",            label: "Favorites",       item: .favorites,      selection: $selection)
                SidebarRow(icon: "clock",           label: "Recently Played", item: .recentlyPlayed, selection: $selection)
            }

            // PLAYLISTS (only when logged in)
            if auth.isLoggedIn {
                playlistsSection
            }

            SidebarSection(title: "Quick Actions") {
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

            // Auth footer
            authFooter

            HStack {
                Text("v0.1.0 · \(library.albums.count) albums")
                    .font(VGFont.label(10))
                    .foregroundStyle(Color.vgTextMuted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.vgSidebar)
        .ignoresSafeArea(.all, edges: .top)
        .sheet(isPresented: $showLogin) {
            LoginSheet()
        }
        .sheet(isPresented: $showNewPlaylist) {
            PlaylistEditSheet(name: "", description: "", isPublic: false) { name, desc, pub in
                Task {
                    if let pl = try? await playlists.create(name: name, description: desc, isPublic: pub) {
                        selection = .playlist(id: pl.id)
                    }
                }
            }
        }
        .task {
            if auth.isLoggedIn { await playlists.load() }
        }
        .onChange(of: auth.isLoggedIn) { _, loggedIn in
            if loggedIn { Task { await playlists.load() } }
        }
    }

    @ViewBuilder
    private var playlistsSection: some View {
        SidebarSection(title: "Playlists") {
            // Liked Music (auto)
            Button {
                selection = .playlistLiked
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .foregroundStyle(selection == .playlistLiked ? Color.vgAccent : Color.vgTextSec)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Liked Music")
                            .font(VGFont.caption(13))
                            .foregroundStyle(selection == .playlistLiked ? Color.vgAccent : Color.vgText)
                        Text("Auto playlist")
                            .font(VGFont.label(10))
                            .foregroundStyle(Color.vgTextMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 34)
                .background(selection == .playlistLiked ? Color.vgAccentSoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)

            // User playlists
            let uid = auth.currentUser?.id ?? ""
            ForEach(playlists.myPlaylists(userId: uid)) { pl in
                Button {
                    selection = .playlist(id: pl.id)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 12))
                            .frame(width: 16)
                            .foregroundStyle(selection == .playlist(id: pl.id) ? Color.vgAccent : Color.vgTextSec)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(pl.name)
                                .font(VGFont.caption(13))
                                .foregroundStyle(selection == .playlist(id: pl.id) ? Color.vgAccent : Color.vgText)
                                .lineLimit(1)
                            Text("\(pl.trackCount) tracks")
                                .font(VGFont.label(10))
                                .foregroundStyle(Color.vgTextMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
                    .background(selection == .playlist(id: pl.id) ? Color.vgAccentSoft : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }

            // New playlist button
            Button { showNewPlaylist = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                        .frame(width: 16)
                        .foregroundStyle(Color.vgTextSec)
                    Text("New playlist")
                        .font(VGFont.caption(13))
                        .foregroundStyle(Color.vgTextSec)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private var authFooter: some View {
        if let user = auth.currentUser {
            HStack(spacing: 8) {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.vgAccent)
                Text(user.username)
                    .font(VGFont.caption(12))
                    .foregroundStyle(Color.vgText)
                Spacer()
                Button { Task { await auth.logout() } } label: {
                    Image(systemName: "arrow.right.square")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.vgTextMuted)
                }
                .buttonStyle(.plain)
                .help("Sign out")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        } else {
            Button { showLogin = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.vgTextSec)
                    Text("Sign in")
                        .font(VGFont.caption(12))
                        .foregroundStyle(Color.vgTextSec)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
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
                .padding(.leading, 2)
            }
            .frame(height: 28)
            .background(isSelected ? Color.vgAccentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

// MARK: - Login sheet

struct LoginSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(AuthStore.self) var auth

    @State private var email = ""
    @State private var password = ""
    @State private var loading = false
    @State private var error = ""

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.lg) {
            Text("Sign in").font(VGFont.title()).foregroundStyle(Color.vgText)

            VStack(alignment: .leading, spacing: 6) {
                Text("EMAIL").font(VGFont.label(10)).tracking(1).foregroundStyle(Color.vgTextMuted)
                TextField("email@example.com", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .font(VGFont.body())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("PASSWORD").font(VGFont.label(10)).tracking(1).foregroundStyle(Color.vgTextMuted)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .font(VGFont.body())
            }

            if !error.isEmpty {
                Text(error).font(VGFont.caption()).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.foregroundStyle(Color.vgTextSec)
                Button(loading ? "…" : "Sign in") {
                    Task { await login() }
                }
                .disabled(loading || email.isEmpty || password.isEmpty)
                .foregroundStyle(Color.vgBg)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.vgAccent)
                .clipShape(Capsule())
            }
        }
        .padding(VGSpace.xl)
        .frame(width: 360)
        .background(Color.vgSurface)
    }

    private func login() async {
        loading = true
        error = ""
        do {
            try await auth.login(email: email, password: password)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }
}
