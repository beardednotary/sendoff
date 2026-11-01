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

    /// What the recipient sees in place of a paid look nobody has paid for. Mirrors
    /// `themes.free_alternative` in 0006_paid_looks.sql.
    var freeAlternative: ThemeID {
        switch self {
        case .goldLeaf: .letterpress
        case .darkroom: .midnightToast
        case .fieldDay: .chalk
        case .letterpress, .midnightToast, .chalk: self
        }
    }
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
    /// Label color on the seal, for the rare theme where neither ink nor paper reaches AA on it.
    var onSeal: HexColor? = nil

    /// One-line description shown on the theme picker.
    var tagline: String

    var isDark: Bool { paper.luminance < 0.4 }

    // Convenience colors
    var paperColor: Color { paper.color }
    var inkColor: Color { ink.color }
    var mutedInkColor: Color { mutedInk.color }
    var sealColor: Color { seal.color }
    var accentColor: Color { accent.color }

    /// Text that sits on top of the seal color: the override, else whichever of ink and paper
    /// reads better on it. Dark themes have light ink, so the seal's own lightness can't decide.
    var onSealInk: HexColor {
        onSeal ?? (ink.contrast(with: seal) >= paper.contrast(with: seal) ? ink : paper)
    }
    var onSealColor: Color { onSealInk.color }

    /// Tertiary text: eyebrows, timestamps. Stays above 4.5:1 on the included themes.
    var faintInkColor: Color { mutedInkColor.opacity(isDark ? 0.8 : 0.88) }

    /// A hairline that reads on this paper.
    var ruleColor: Color { inkColor.opacity(0.1) }

    /// Fields and cards: one step up from the paper.
    var raisedPaperColor: Color { isDark ? inkColor.opacity(0.06) : Color.white }

    /// Secondary pills and circle buttons.
    var controlColor: Color { inkColor.opacity(isDark ? 0.12 : 0.07) }
}

// MARK: - Catalog

enum ThemeCatalog {
    static let all: [SendoffTheme] = [
        SendoffTheme(
            id: .letterpress, name: "Paper", premium: false,
            paper: "#F5F3EF", ink: "#141413", mutedInk: "#55524D", seal: "#141413", accent: "#E8E5DF",
            motion: .lift, texture: .paper, radius: 22,
            tagline: "Warm white, black ink. Quiet and clear."
        ),
        SendoffTheme(
            id: .midnightToast, name: "Evening", premium: false,
            paper: "#0E0E0D", ink: "#F3F1EC", mutedInk: "#ADAAA3", seal: "#F3F1EC", accent: "#262624",
            motion: .lift, texture: .linen, radius: 22,
            tagline: "Near-black, warm white type. For the evening it opens."
        ),
        SendoffTheme(
            id: .chalk, name: "Blackboard", premium: false,
            paper: "#18211C", ink: "#EEF0EA", mutedInk: "#A7B1A9", seal: "#EEF0EA", accent: "#26322B",
            motion: .turn, texture: .chalk, radius: 22,
            tagline: "Deep green-black. The board on the last day of school."
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
            motion: .turn, texture: .grass, radius: 8, onSeal: "#1F5A38",
            tagline: "End of season. Chalk lines and jersey numbers."
        ),
    ]

    static func theme(_ id: ThemeID) -> SendoffTheme {
        all.first { $0.id == id } ?? all[0]
    }

    static var included: [SendoffTheme] { all.filter { !$0.premium } }

    /// The organizer's own screens: Evening in dark mode, Paper in light.
    static func app(_ scheme: ColorScheme) -> SendoffTheme { theme(scheme == .dark ? .midnightToast : .letterpress) }
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

/// New York for who it is for and what people wrote; SF Pro for the app around it.
/// Nine sizes: 60 48 40 28 20 17 15 13 11.
enum Typeface {
    /// Names and headlines. New York Regular; pair with `.displayTracking(size)`.
    static func display(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .regular, design: .serif)
    }

    /// A contribution, sized by how much there is of it.
    static func entry(length: Int) -> Font {
        .system(size: length <= 140 ? 28 : length <= 420 ? 22 : 20, weight: .regular, design: .serif)
    }

    /// The writing field and short serif lines.
    static var entry: Font { .system(size: 20, weight: .regular, design: .serif) }

    /// List names: "Maria Reyes".
    static var name: Font { .system(size: 20, weight: .regular, design: .serif) }

    /// Section titles and sheet headlines.
    static var title: Font { .system(size: 28, weight: .regular, design: .serif) }

    static var ui: Font { .system(size: 17, weight: .regular) }
    static var uiStrong: Font { .system(size: 17, weight: .semibold) }
    static var body: Font { .system(size: 15, weight: .regular) }
    static var bodyStrong: Font { .system(size: 15, weight: .semibold) }
    static var caption: Font { .system(size: 13, weight: .regular) }

    /// Tracked uppercase label above a headline.
    static var eyebrow: Font { .system(size: 11, weight: .semibold) }

    /// "— Dan Okafor · Your manager, somehow"
    static var signature: Font { .system(size: 15, weight: .semibold) }
}

extension View {
    /// Display type sits tighter than text.
    func displayTracking(_ size: CGFloat) -> some View { tracking(-size * 0.02) }
}

// MARK: - Motion

enum Motion {
    static let lift = Animation.spring(response: 0.6, dampingFraction: 0.86)
    static let turn = Animation.spring(response: 0.5, dampingFraction: 0.9)
    static let settle = Animation.spring(response: 0.45, dampingFraction: 0.92)
    static let fade = Animation.easeInOut(duration: 0.35)
    static let tap = Animation.easeOut(duration: 0.16)
    /// How long the seal is held before it opens.
    static let holdToOpen: Double = 1.0
}
