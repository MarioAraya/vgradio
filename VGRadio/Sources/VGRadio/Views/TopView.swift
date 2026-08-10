import SwiftUI

private struct TopPlatform: Identifiable {
    let id: String
    let label: String
}

private let topPlatforms: [TopPlatform] = [
    TopPlatform(id: "ps1",    label: "PS1"),
    TopPlatform(id: "ps2",    label: "PS2"),
    TopPlatform(id: "ps3",    label: "PS3"),
    TopPlatform(id: "ps4",    label: "PS4"),
    TopPlatform(id: "ps5",    label: "PS5"),
    TopPlatform(id: "switch", label: "Switch"),
    TopPlatform(id: "wii",    label: "Wii"),
    TopPlatform(id: "wiiu",   label: "Wii U"),
    TopPlatform(id: "n64",    label: "N64"),
    TopPlatform(id: "xbox",   label: "Xbox"),
]

struct TopView: View {
    @State private var entries: [String: [Top12Entry]] = [:]
    @State private var errors: [String: String] = [:]
    @State private var adding: Set<String> = []

    private let columns = [GridItem(.adaptive(minimum: 140, maximum: 160), spacing: VGSpace.md)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top 12")
                        .font(VGFont.title())
                        .foregroundStyle(Color.vgText)
                    Text("Los álbumes más populares de khinsider, por plataforma")
                        .font(VGFont.body())
                        .foregroundStyle(Color.vgTextMuted)
                }
                .padding(.top, VGSpace.sm)

                ForEach(topPlatforms) { platform in
                    platformSection(platform)
                }
            }
            .padding(.horizontal, VGSpace.xl)
            .padding(.bottom, VGSpace.xl)
        }
        .background(Color.vgBg)
        .task { await loadAll() }
    }

    @ViewBuilder
    private func platformSection(_ platform: TopPlatform) -> some View {
        VStack(alignment: .leading, spacing: VGSpace.sm) {
            Text(platform.label)
                .font(VGFont.heading())
                .foregroundStyle(Color.vgText)
                .padding(.bottom, 6)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color.vgSeparator).frame(height: 1)
                }

            if let err = errors[platform.id] {
                Text("Error: \(err)")
                    .font(VGFont.caption())
                    .foregroundStyle(Color.vgTextMuted)
            } else if let items = entries[platform.id] {
                LazyVGrid(columns: columns, spacing: VGSpace.md) {
                    ForEach(items) { entry in
                        Top12Card(entry: entry, isAdding: adding.contains(entry.sourceUrl)) {
                            Task { await addToLibrary(entry) }
                        }
                    }
                }
            } else {
                ProgressView().padding(.vertical, 12)
            }
        }
    }

    private func loadAll() async {
        await withTaskGroup(of: (String, Result<[Top12Entry], Error>).self) { group in
            for platform in topPlatforms {
                group.addTask {
                    do {
                        let items = try await APIClient.shared.top12(platform: platform.id)
                        return (platform.id, .success(items))
                    } catch {
                        return (platform.id, .failure(error))
                    }
                }
            }
            for await (id, result) in group {
                switch result {
                case .success(let items): entries[id] = items
                case .failure(let error): errors[id] = error.localizedDescription
                }
            }
        }
    }

    private func addToLibrary(_ entry: Top12Entry) async {
        guard !adding.contains(entry.sourceUrl) else { return }
        adding.insert(entry.sourceUrl)
        defer { adding.remove(entry.sourceUrl) }
        _ = try? await APIClient.shared.addAlbum(url: entry.sourceUrl)
    }
}

private struct Top12Card: View {
    let entry: Top12Entry
    let isAdding: Bool
    let onAdd: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Button {
                    if let url = URL(string: entry.sourceUrl) { NSWorkspace.shared.open(url) }
                } label: {
                    AsyncImage(url: URL(string: entry.coverThumbUrl)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.vgSurfaceHi
                        }
                    }
                    .frame(width: 140, height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("\(entry.title) — abrir en khinsider")

                Button(action: onAdd) {
                    Group {
                        if isAdding {
                            ProgressView().progressViewStyle(.circular).scaleEffect(0.5)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Color.white)
                    .background(Color.black.opacity(0.65))
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isAdding)
                .opacity(isHovered || isAdding ? 1 : 0)
                .padding(6)
                .help("Add to library")
            }
            .onHover { isHovered = $0 }

            Text(entry.title)
                .font(VGFont.caption(12))
                .foregroundStyle(Color.vgTextSec)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)
        }
    }
}
