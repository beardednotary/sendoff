import SwiftUI

// MARK: - Theme identity

enum ThemeID: String, Codable, CaseIterable, Identifiable {
    case letterpress
    case midnightToast = "midnight_toast"
    case chalk
    case goldLeaf = "gold_leaf"
    case darkroom
    case fieldDay = "field_day"

    var id: String { rawValue }
}

enum ThemeMotion: String, Codable {
    /// Envelope flap lifts, pages turn with depth.
    case lift
    /// Flat page turn, chalk-on-board feel.
    case turn
    /// Crossfades only. Also used when Reduce Motion is on.
    case fade
}

enum PaperTexture: String, Codable {
    case paper, linen, chalk, grain, grass
}

// MARK: - Theme

/// A theme is data. Premium themes can arrive from the server as JSON with no app update.
struct SendoffTheme: Identifiable, Codable, Hashable {
    var id: ThemeID
    var name: String
    var premium: Bool
    var paper: HexColor
    var ink: HexColor
    var mutedInk: HexColor
    var seal: HexColor
    var accent: HexColor
    var motion: ThemeMotion
    var texture: PaperTexture
    var radius: CGFloat
    var foil: Bool = false

    /// One-line description shown on the theme picker.
    var tagline: String

    var isDark: Bool { paper.luminance < 0.4 }

    // Convenience colors
    var paperColor: Color { paper.color }
    var inkColor: Color { ink.color }
    var mutedInkColor: Color { mutedInk.color }
    var sealColor: Color { seal.color }
    var accentColor: Color { accent.color }

    /// Text that sits on top of the seal color.
    var onSealColor: Color { seal.luminance > 0.5 ? ink.color : paper.color }

    /// A hairline that reads on this paper.
    var ruleColor: Color { inkColor.opacity(isDark ? 0.22 : 0.14) }

    /// Slightly raised surface (entry card, sheet) on this paper.
    var raisedPaperColor: Color { isDark ? inkColor.opacity(0.06) : Color.white.opacity(0.45) }
}

// MARK: - Catalog

enum ThemeCatalog {
    static let all: [SendoffTheme] = [
        SendoffTheme(
            id: .letterpress, name: "Letterpress", premium: false,
            paper: "#F4EFE6", ink: "#1F1D1A", mutedInk: "#6B655C", seal: "#C8442B", accent: "#D9C7A3",
            motion: .lift, texture: .paper, radius: 6,
            tagline: "A hand-printed program. Cream paper, vermilion seal."
        ),
        SendoffTheme(
            id: .midnightToast, name: "Midnight Toast", premium: false,
            paper: "#0F1B2D", ink: "#F2EBDD", mutedInk: "#A79F8E", seal: "#C9A24A", accent: "#2A3A55",
            motion: .lift, texture: .linen, radius: 10,
            tagline: "A dinner toast. Dark, warm, candle-lit."
        ),
        SendoffTheme(
            id: .chalk, name: "Chalk", premium: false,
            paper: "#2F4A3E", ink: "#F7F3E8", mutedInk: "#B8C4B9", seal: "#E9C46A", accent: "#3E5C4E",
            motion: .turn, texture: .chalk, radius: 4,
            tagline: "The board on the last day of school."
        ),
        SendoffTheme(
            id: .goldLeaf, name: "Gold Leaf", premium: true,
            paper: "#F6F1E7", ink: "#1F1D1A", mutedInk: "#6B655C", seal: "#B8912E", accent: "#E8D9B5",
            motion: .lift, texture: .paper, radius: 6, foil: true,
            tagline: "Letterpress with real foil that catches the light."
        ),
        SendoffTheme(
            id: .darkroom, name: "Darkroom", premium: true,
            paper: "#0B0B0C", ink: "#EDEDED", mutedInk: "#8E8E8E", seal: "#E04E39", accent: "#1E1E20",
            motion: .fade, texture: .grain, radius: 2,
            tagline: "Video first. Letterboxed, grain, quiet."
        ),
        SendoffTheme(
            id: .fieldDay, name: "Field Day", premium: true,
            paper: "#2E7D4F", ink: "#FFFFFF", mutedInk: "#CFE6D7", seal: "#F4D35E", accent: "#256A42",
            motion: .turn, texture: .grass, radius: 8,
            tagline: "End of season. Chalk lines and jersey numbers."
        ),
    ]

    static func theme(_ id: ThemeID) -> SendoffTheme {
        all.first { $0.id == id } ?? all[0]
    }

    static var included: [SendoffTheme] { all.filter { !$0.premium } }
    static var premium: [SendoffTheme] { all.filter(\.premium) }
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: SendoffTheme = ThemeCatalog.theme(.letterpress)
}

extension EnvironmentValues {
    var theme: SendoffTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension View {
    func sendoffTheme(_ theme: SendoffTheme) -> some View {
        environment(\.theme, theme)
            .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

// MARK: - Hex colors

/// A color stored as a hex string so themes round-trip through JSON.
struct HexColor: Codable, Hashable, ExpressibleByStringLiteral {
    let hex: String

    init(_ hex: String) { self.hex = hex.uppercased() }
    init(stringLiteral value: String) { self.init(value) }

    init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hex)
    }

    var rgb: (r: Double, g: Double, b: Double) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return (0, 0, 0) }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    var color: Color {
        let c = rgb
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: 1)
    }

    /// Relative luminance per WCAG.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let c = rgb
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    /// WCAG contrast ratio against another color.
    func contrast(with other: HexColor) -> Double {
        let a = luminance, b = other.luminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

// MARK: - Typography

enum Typeface {
    /// Recipient name on the cover. New York, semibold, tight.
    static func display(_ size: CGFloat = 44) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// Entry body. The contributor's voice.
    static var entry: Font { .system(size: 19, weight: .regular, design: .serif) }

    /// "Dana · Your 2019 intern"
    static var signature: Font { .system(size: 17, weight: .regular, design: .serif).italic() }

    /// Section titles in the organizer's screens.
    static var title: Font { .system(size: 28, weight: .semibold, design: .serif) }

    /// Controls and metadata. The app getting out of the way.
    static var ui: Font { .system(size: 16, weight: .regular) }
    static var uiStrong: Font { .system(size: 16, weight: .semibold) }
    static var caption: Font { .system(size: 13, weight: .regular) }

    /// The Stamp: small caps, tracked out.
    static var stamp: Font { .system(size: 12, weight: .semibold) }
}

// MARK: - Motion

enum Motion {
    static let lift = Animation.spring(response: 0.6, dampingFraction: 0.82)
    static let turn = Animation.easeInOut(duration: 0.45)
    static let settle = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let fade = Animation.easeInOut(duration: 0.35)
    static let tap = Animation.easeOut(duration: 0.18)
}
