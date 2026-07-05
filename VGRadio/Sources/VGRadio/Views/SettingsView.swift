import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.lg) {
            HStack {
                Text("Settings").font(VGFont.title()).foregroundStyle(Color.vgText)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.vgTextMuted)
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: VGSpace.md) {
                Image(systemName: "gearshape")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.vgTextMuted)
                Text("Nada por acá todavía")
                    .font(VGFont.body())
                    .foregroundStyle(Color.vgTextSec)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
        .padding(VGSpace.xl)
        .frame(width: 420)
        .background(Color.vgSurface)
    }
}
