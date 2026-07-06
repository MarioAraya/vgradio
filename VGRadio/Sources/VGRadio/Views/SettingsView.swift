import SwiftUI

private enum BackendStatus {
    case checking, online, offline
}

struct SettingsView: View {
    @Binding var isPresented: Bool
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
