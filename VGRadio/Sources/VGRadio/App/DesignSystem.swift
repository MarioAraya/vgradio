import SwiftUI

// MARK: - Colors

extension Color {
    static let vgBg         = Color(hex: "#0F0F13")
    static let vgSidebar    = Color(hex: "#1A1A22")
    static let vgSurface    = Color(hex: "#1E1E28")
    static let vgSurfaceHi  = Color(hex: "#25252F")
    static let vgAccent     = Color(hex: "#C9952A")
    static let vgAccentSoft = Color(hex: "#C9952A").opacity(0.18)
    static let vgStar       = Color(hex: "#F5A623")
    static let vgText       = Color.white
    static let vgTextSec    = Color(white: 0.55)
    static let vgTextMuted  = Color(white: 0.35)
    static let vgSeparator  = Color(white: 1, opacity: 0.07)

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
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .bold, design: .default) }
    static func heading(_ size: CGFloat = 15) -> Font { .system(size: size, weight: .semibold) }
    static func body(_ size: CGFloat = 13) -> Font { .system(size: size, weight: .regular) }
    static func caption(_ size: CGFloat = 11) -> Font { .system(size: size, weight: .regular) }
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, weight: .regular, design: .monospaced) }
}

// MARK: - Spacing

enum VGSpace {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
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
