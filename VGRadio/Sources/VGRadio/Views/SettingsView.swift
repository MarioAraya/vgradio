import SwiftUI

private enum BackendStatus {
    case checking, online, offline
}

struct SettingsView: View {
    @Binding var isPresented: Bool
    @Environment(OfflineStore.self) var offline
    @State private var status: BackendStatus = .checking

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.lg) {
            HStack {
                Text("Settings").font(VGFont.title()).foregroundStyle(Color.vgText)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.vgTextMuted)
                }
                .buttonStyle(.plain)
            }

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
                    Button("Elegir…") { offline.chooseFolder() }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.vgAccent)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(VGSpace.xl)
        .frame(width: 420)
        .background(Color.vgSurface)
        .task { await checkStatus() }
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
