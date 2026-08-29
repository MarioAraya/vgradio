import SwiftUI
import AppKit

// MARK: - Colors

extension Color {
    /// Resolves per appearance, so every token follows the dark/green-light theme
    /// selected in Settings (which drives `NSApp.appearance`).
    static func vgDynamic(dark: String, light: String) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        })
    }

    // Dark values converted from oklch in styles.css; light values are the green theme.
    static let vgBg         = vgDynamic(dark: "#131320", light: "#F2F6F2")
    static let vgSidebar    = vgDynamic(dark: "#0F0F1A", light: "#E6EEE7")
    static let vgSurface    = vgDynamic(dark: "#17172A", light: "#FFFFFF")
    static let vgSurfaceHi  = vgDynamic(dark: "#1C1C30", light: "#EDF3EE")
    static let vgMuted      = vgDynamic(dark: "#1B1B2C", light: "#E1EAE2")
    static let vgAccent     = vgDynamic(dark: "#CBA827", light: "#2F8F4E")
    static let vgAccentSoft = vgDynamic(dark: "#CBA8271A", light: "#2F8F4E1F")  // primary/10
    static let vgAccentBg   = vgDynamic(dark: "#CBA82714", light: "#2F8F4E17")  // primary/8 (playing row)
    static let vgAccentHi   = vgDynamic(dark: "#CBA8272E", light: "#2F8F4E38")  // primary/18
    static let vgOnAccent   = vgDynamic(dark: "#131320", light: "#FFFFFF")      // text on an accent fill
    static let vgStar       = vgAccent  // same as accent (fill-primary)
    static let vgText       = vgDynamic(dark: "#F0F0F5", light: "#14251B")
    static let vgTextSec    = vgDynamic(dark: "#8A8AA0", light: "#55685C")
    static let vgTextMuted  = vgDynamic(dark: "#8A8AA099", light: "#55685CB3")
    static let vgSeparator  = vgDynamic(dark: "#FFFFFF14", light: "#14251B1F")  // border
    static let vgBorder60   = vgDynamic(dark: "#FFFFFF0C", light: "#14251B12")  // border/60

    // Neutral overlays: hover states, chips, inputs.
    static let vgHover      = vgDynamic(dark: "#FFFFFF0A", light: "#14251B0D")
    static let vgHoverMd    = vgDynamic(dark: "#FFFFFF0F", light: "#14251B14")
    static let vgHoverHi    = vgDynamic(dark: "#FFFFFF1F", light: "#14251B29")

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

extension NSColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .init(charactersIn: "#"))
        if s.count == 6 { s += "FF" }
        let v = UInt64(s, radix: 16) ?? 0
        self.init(
            srgbRed: CGFloat((v >> 24) & 0xFF) / 255,
            green:   CGFloat((v >> 16) & 0xFF) / 255,
            blue:    CGFloat((v >>  8) & 0xFF) / 255,
            alpha:   CGFloat(v & 0xFF) / 255
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
    static let remoteBannerHeight: CGFloat = 26
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
                Capsule().fill(Color.vgHoverHi)
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
