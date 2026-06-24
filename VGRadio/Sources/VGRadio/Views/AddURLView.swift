import SwiftUI

struct AddURLView: View {
    @Binding var isPresented: Bool
    @Environment(LibraryStore.self) var library
    @State private var urlText = ""
    @State private var phase: Phase = .idle
    @State private var fakeProgress: Double = 0
    @FocusState private var urlFocused: Bool
    private let progressTimer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect()

    enum Phase { case idle, loading, done, failed(String) }

    var body: some View {
        VStack(spacing: 0) {
            // Header — h-10, border-b
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.vgAccent)
                Text("Import Album")
                    .font(VGFont.caption(12))
                    .fontWeight(.medium)
                    .foregroundStyle(Color.vgText)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.vgTextSec)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .overlay(alignment: .bottom) {
                Divider().overlay(Color.vgSeparator)
            }

            VStack(alignment: .leading, spacing: 16) {
                // URL input — h-10, bg white/5, border white/10
                TextField("https://downloads.khinsider.com/game-soundtracks/album/...", text: $urlText)
                    .textFieldStyle(.plain)
                    .font(VGFont.body(13))
                    .foregroundStyle(Color.vgText)
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .focused($urlFocused)
                    .disabled(isLoading)
                    .onSubmit { Task { await submit() } }

                // Status area
                switch phase {
                case .idle:
                    Text("Paste a khinsider album URL above")
                        .font(VGFont.caption(12))
                        .foregroundStyle(Color.vgTextMuted)

                case .loading:
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Importing…")
                                .font(VGFont.caption(12))
                                .foregroundStyle(Color.vgTextSec)
                            Spacer()
                            Text("\(Int(fakeProgress * 100))%")
                                .font(VGFont.mono(11))
                                .foregroundStyle(Color.vgAccent)
                                .monospacedDigit()
                        }
                        // Animated progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.10))
                                Capsule()
                                    .fill(Color.vgAccent)
                                    .frame(width: geo.size.width * fakeProgress)
                                    .animation(.easeInOut(duration: 0.15), value: fakeProgress)
                            }
                        }
                        .frame(height: 4)
                    }

                case .done:
                    Label("Album imported successfully!", systemImage: "checkmark.circle.fill")
                        .font(VGFont.caption(12))
                        .foregroundStyle(.green)

                case .failed(let msg):
                    Label(msg, systemImage: "xmark.circle.fill")
                        .font(VGFont.caption(12))
                        .foregroundStyle(.red)
                        .lineLimit(3)
                }

                // Actions
                HStack {
                    Spacer()
                    Button("Import") { Task { await submit() } }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.vgBg)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Color.vgAccent.opacity(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading ? 0.5 : 1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .buttonStyle(.plain)
                        .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
            .padding(16)
        }
        .background(Color.vgSidebar)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.vgSeparator))
        .frame(width: 460)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { urlFocused = true }
        }
        .onReceive(progressTimer) { _ in
            guard isLoading else { return }
            // Fake progress: fast to 70%, then slow, never reaches 100%
            let delta: Double = fakeProgress < 0.7 ? 0.012 : 0.003
            fakeProgress = min(0.92, fakeProgress + delta)
        }
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    private func submit() async {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        fakeProgress = 0
        phase = .loading
        do {
            try await library.importAlbum(url: url)
            fakeProgress = 1.0
            try? await Task.sleep(nanoseconds: 300_000_000)
            phase = .done
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            isPresented = false
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}

struct VGButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.vgBg)
            .padding(.horizontal, 16)
            .frame(height: 32)
            .background(Color.vgAccent.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
