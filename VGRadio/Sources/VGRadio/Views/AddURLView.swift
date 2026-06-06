import SwiftUI

struct AddURLView: View {
    @Binding var isPresented: Bool
    @Environment(LibraryStore.self) var library
    @State private var urlText = ""
    @State private var phase: Phase = .idle

    enum Phase { case idle, loading(String), done, failed(String) }

    var body: some View {
        VStack(alignment: .leading, spacing: VGSpace.xl) {
            // Header
            HStack {
                Image(systemName: "link")
                    .foregroundStyle(Color.vgAccent)
                Text("Add Album from URL")
                    .font(VGFont.heading(15))
                    .foregroundStyle(Color.vgText)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(Color.vgTextSec)
                }
                .buttonStyle(.plain)
            }

            // Input
            TextField("Paste album URL...", text: $urlText)
                .textFieldStyle(.plain)
                .font(VGFont.body())
                .foregroundStyle(Color.vgText)
                .padding(VGSpace.md)
                .background(Color.vgSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.vgAccent, lineWidth: 1.5)
                )
                .disabled(isLoading)

            // Status
            switch phase {
            case .idle:
                EmptyView()
            case .loading(let msg):
                HStack(spacing: VGSpace.sm) {
                    ProgressView().scaleEffect(0.7)
                    Text(msg).font(VGFont.body()).foregroundStyle(Color.vgTextSec)
                }
            case .done:
                Label("Album added to library!", systemImage: "checkmark.circle.fill")
                    .font(VGFont.body())
                    .foregroundStyle(.green)
            case .failed(let msg):
                Label(msg, systemImage: "xmark.circle.fill")
                    .font(VGFont.body())
                    .foregroundStyle(.red)
                    .lineLimit(3)
            }

            // Actions
            HStack {
                Spacer()
                Button("Import") { Task { await submit() } }
                    .buttonStyle(VGButtonStyle())
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
        }
        .padding(VGSpace.xl)
        .background(Color.vgSidebar)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 520)
        .onSubmit { Task { await submit() } }
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    private func submit() async {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return }
        phase = .loading("Scraping album…")
        do {
            let job = try await library.addAlbum(url: url)
            phase = .loading("Processing…")
            _ = try await library.pollJob(job.jobId)
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
            .font(VGFont.heading(13))
            .foregroundStyle(.white)
            .padding(.horizontal, VGSpace.lg)
            .padding(.vertical, VGSpace.sm)
            .background(Color.vgAccent.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
