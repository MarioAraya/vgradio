import SwiftUI

private enum BackendStatus {
    case checking, online, offline
}

struct SettingsView: View {
    @Environment(OfflineStore.self) var offline
    @Environment(LibraryStore.self) var library
    @State private var status: BackendStatus = .checking
    @State private var pendingDeleteAlbumID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VGSpace.lg) {
                Text("Settings")
                    .font(VGFont.title())
                    .foregroundStyle(Color.vgText)
                    .padding(.top, VGSpace.md)

                VStack(alignment: .leading, spacing: VGSpace.sm) {
                    Text("BACKEND")
                        .font(VGFont.label(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.vgTextMuted)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextSec)
                        Spacer()
                        Button {
                            Task { await checkStatus() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(Color.vgTextMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: VGSpace.sm) {
                    Text("OFFLINE")
                        .font(VGFont.label(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.vgTextMuted)

                    @Bindable var offline = offline

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Modo offline")
                                .font(VGFont.body())
                                .foregroundStyle(Color.vgTextSec)
                            Text(offline.isBackendReachable ? "Backend accesible" : "Sin conexión al backend — offline activado automáticamente")
                                .font(VGFont.caption(11))
                                .foregroundStyle(offline.isBackendReachable ? Color.vgTextMuted : Color.vgAccent)
                        }
                        Spacer()
                        Toggle("", isOn: $offline.offlineModeEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Carpeta de descargas")
                                .font(VGFont.body())
                                .foregroundStyle(Color.vgTextSec)
                            Text(offline.folderDisplayPath)
                                .font(VGFont.caption(11))
                                .foregroundStyle(Color.vgTextMuted)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if offline.hasFolder {
                                Text(ByteCountFormatter.string(fromByteCount: offline.offlineStorageBytes, countStyle: .file) + " descargados")
                                    .font(VGFont.caption(11))
                                    .foregroundStyle(Color.vgTextMuted)
                            }
                        }
                        Spacer()
                        if offline.hasFolder {
                            Button("Abrir en Finder") { offline.revealFolderInFinder() }
                                .buttonStyle(.plain)
                                .foregroundStyle(Color.vgAccent)
                        }
                        Button("Elegir…") { offline.chooseFolder() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.vgAccent)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: VGSpace.sm) {
                    Text("ÁLBUMES DESCARGADOS")
                        .font(VGFont.label(10))
                        .tracking(1.2)
                        .foregroundStyle(Color.vgTextMuted)

                    if offline.grouped.isEmpty {
                        Text("Ningún álbum descargado todavía.")
                            .font(VGFont.body())
                            .foregroundStyle(Color.vgTextMuted)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(offline.grouped, id: \.albumId) { group in
                                downloadedAlbumRow(group)
                            }
                        }
                    }
                }
            }
            .padding(VGSpace.xl)
        }
        .background(Color.vgSurface)
        .task { await checkStatus() }
        .confirmationDialog(
            "¿Eliminar esta descarga de tu Mac?",
            isPresented: Binding(
                get: { pendingDeleteAlbumID != nil },
                set: { if !$0 { pendingDeleteAlbumID = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                if let id = pendingDeleteAlbumID { offline.removeAllOffline(albumID: id) }
                pendingDeleteAlbumID = nil
            }
            Button("Cancelar", role: .cancel) { pendingDeleteAlbumID = nil }
        } message: {
            Text("Se borran los archivos mp3 guardados en esta Mac. El álbum sigue disponible en streaming.")
        }
    }

    private func downloadedAlbumRow(_ group: (albumId: String, albumTitle: String, platform: String, year: Int, coverUrl: String, tracks: [DownloadedTrack])) -> some View {
        let totalTracks = library.albums.first(where: { $0.id == group.albumId })?.trackCount ?? group.tracks.count
        let bytes = offline.offlineStorageBytes(albumID: group.albumId)
        return HStack(spacing: VGSpace.md) {
            AsyncImage(url: AlbumCoverView.resolveURL(group.coverUrl)) { phase in
                switch phase {
                case .success(let img): img.resizable().aspectRatio(contentMode: .fill)
                default: AlbumLetterArt(title: group.albumTitle, size: 44)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(group.albumTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.vgText)
                    .lineLimit(1)
                Text("\(group.tracks.count)/\(totalTracks) tracks · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)) · \(group.platform) · \(String(group.year))")
                    .font(VGFont.caption(11))
                    .foregroundStyle(Color.vgTextMuted)
            }

            Spacer()

            Button("Eliminar") { pendingDeleteAlbumID = group.albumId }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.4)))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var statusColor: Color {
        switch status {
        case .checking: return Color.vgTextMuted
        case .online: return .green
        case .offline: return .red
        }
    }

    private var statusText: String {
        switch status {
        case .checking: return "Checking…"
        case .online: return "Corriendo"
        case .offline: return "No responde"
        }
    }

    private func checkStatus() async {
        status = .checking
        status = await APIClient.shared.healthCheck() ? .online : .offline
    }
}
