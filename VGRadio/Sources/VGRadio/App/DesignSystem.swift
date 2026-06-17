import SwiftUI

// MARK: - Colors

extension Color {
    // Converted from oklch values in styles.css
    static let vgBg         = Color(hex: "#131320")  // oklch(0.18 0.02 270)
    static let vgSidebar    = Color(hex: "#0F0F1A")  // oklch(0.155 0.018 270)
    static let vgSurface    = Color(hex: "#17172A")  // oklch(0.21 0.022 270) card
    static let vgSurfaceHi  = Color(hex: "#1C1C30")  // oklch(0.25 0.022 270) secondary
    static let vgMuted      = Color(hex: "#1B1B2C")  // oklch(0.24 0.02 270)
    static let vgAccent     = Color(hex: "#CBA827")  // oklch(0.78 0.14 75) primary
    static let vgAccentSoft = Color(hex: "#CBA827").opacity(0.10)   // primary/10
    static let vgAccentBg   = Color(hex: "#CBA827").opacity(0.08)   // primary/8 (playing row)
    static let vgStar       = Color(hex: "#CBA827")  // same as accent (fill-primary)
    static let vgText       = Color(hex: "#F0F0F5")  // oklch(0.95 0.005 270) foreground
    static let vgTextSec    = Color(hex: "#8A8AA0")  // oklch(0.65 0.015 270) muted-foreground
    static let vgTextMuted  = Color(hex: "#8A8AA0").opacity(0.60)
    static let vgSeparator  = Color(white: 1, opacity: 0.08)   // oklch(1 0 0 / 8%) border
    static let vgBorder60   = Color(white: 1, opacity: 0.048)  // border/60

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(
            red:   Double((v >> 24) & 0xFF) / 255,
            green: Double((v >> 16) & 0xFF) / 255,
            blue:  Double((v >>  8) & 0xFF) / 255,
            opacity: Double(v & 0xFF) / 255
        )
    }
}

// MARK: - Typography

enum VGFont {
    static func display(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .bold) }
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .bold) }
    static func heading(_ size: CGFloat = 14) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular) }
    static func caption(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .regular) }
    static func label(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .regular) }
    static func mono(_ size: CGFloat = 10) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
}

// MARK: - Spacing

enum VGSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// MARK: - Layout constants

enum VGLayout {
    static let sidebarWidth: CGFloat    = 180
    static let playerBarHeight: CGFloat = 56
    static let albumCoverDetail: CGFloat = 220
    static let albumCoverPlayer: CGFloat = 44
    static let albumCoverGrid: CGFloat   = 120
    static let playBtnSize: CGFloat      = 32
    static let trackRowHeight: CGFloat   = 40
}

// MARK: - Thin scrubber track (replaces native Slider)

struct ThinProgressTrack: View {
    let fraction: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(Color.vgAccent)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * fraction)))
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                onSeek(min(1, max(0, v.location.x / geo.size.width)))
            })
        }
        .frame(height: 4)
    }
}

// MARK: - Album art placeholder

/// Generates a colored gradient square with a letter — used when no cover art is available.
struct AlbumLetterArt: View {
    let title: String
    let size: CGFloat

    private var letter: String { String(title.prefix(1).uppercased()) }

    private var gradient: LinearGradient {
        let hue = Double(abs(title.hashValue) % 360) / 360
        let c1 = Color(hue: hue, saturation: 0.7, brightness: 0.6)
        let c2 = Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.8, brightness: 0.4)
        return LinearGradient(colors: [c1, c2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.15)
                .fill(gradient)
            Text(letter)
                .font(.system(size: size * 0.45, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: size, height: size)
    }
}
