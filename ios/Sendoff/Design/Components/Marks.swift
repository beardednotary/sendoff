import SwiftUI

// The pieces every screen is built from. No illustration and no ornament: the photographs and
// the words people wrote are the only colour. See design/v2/DIRECTION.md.

// MARK: - Ground

/// The page: the theme's paper, flat, edge to edge.
struct Paper: View {
    @Environment(\.theme) private var theme

    var body: some View {
        theme.paperColor.ignoresSafeArea()
    }
}

/// The organizer's screens follow the system appearance: Evening in dark mode, Paper in light.
struct AppThemeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.environment(\.theme, ThemeCatalog.app(scheme))
    }
}

extension View {
    func appTheme() -> some View { modifier(AppThemeModifier()) }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state ^= state >> 12; state ^= state << 25; state ^= state >> 27
        return Double((state &* 2685821657736338717) >> 11) / Double(1 << 53)
    }
}

// MARK: - Seal

/// The seal: the recipient's initial inside two fine rings, blind-embossed, no colour.
/// `progress` draws the outer ring closed while the recipient holds it open.
struct Seal: View {
    @Environment(\.theme) private var theme
    var initial: String
    var size: CGFloat = 88
    var progress: Double = 0
    var ink: Color? = nil

    var body: some View {
        let color = ink ?? theme.inkColor
        ZStack {
            Circle().strokeBorder(color.opacity(progress > 0 ? 0.3 : 1), lineWidth: 1)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: max(1.5, size * 0.014), lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(max(0.75, size * 0.007))
            Circle().strokeBorder(color.opacity(0.18), lineWidth: 1).padding(size * 0.05)
            Text(initial)
                .font(.system(size: size * 0.43, weight: .regular, design: .serif))
                .foregroundStyle(color)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Seal with the letter \(initial)")
    }
}

// MARK: - Labels

/// Tracked uppercase label that sits above a headline: "NEW JOB", "IN THE ENVELOPE · 7".
struct Eyebrow: View {
    @Environment(\.theme) private var theme
    var text: String
    var tint: Color? = nil

    var body: some View {
        Text(text.uppercased())
            .font(Typeface.eyebrow)
            .tracking(1.5)
            .lineLimit(1)
            .foregroundStyle(tint ?? theme.faintInkColor)
    }
}

/// An icon and a line of state: "Collecting until Sunday, November 8".
struct MetaLine: View {
    @Environment(\.theme) private var theme
    var systemImage: String
    var text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(theme.faintInkColor)
                .frame(width: 20)
            Text(text)
                .font(Typeface.body)
                .foregroundStyle(theme.mutedInkColor)
        }
    }
}

/// A hairline.
struct Rule: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Rectangle().fill(theme.ruleColor).frame(height: 1)
    }
}

// MARK: - Buttons

/// The one important action on a screen: a filled pill in the theme's seal colour.
struct PrimaryButton: View {
    @Environment(\.theme) private var theme
    var title: String
    var systemImage: String? = nil
    var fill = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PillLabel(title: title, systemImage: systemImage, fill: fill)
                .foregroundStyle(theme.onSealColor)
                .background(theme.sealColor, in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// Everything that is not the one important action.
struct SecondaryButton: View {
    @Environment(\.theme) private var theme
    var title: String
    var systemImage: String? = nil
    var fill = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            PillLabel(title: title, systemImage: systemImage, fill: fill)
                .foregroundStyle(theme.inkColor)
                .background(theme.controlColor, in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}

/// The inside of a pill, for links and share sheets that bring their own button.
struct PillLabel: View {
    var title: String
    var systemImage: String? = nil
    var fill = true
    var small = false
    /// Arrows go after the word: "Begin →".
    var iconTrailing = false

    var body: some View {
        HStack(spacing: 8) {
            if let systemImage, !iconTrailing { icon(systemImage) }
            Text(title).lineLimit(1)
            if let systemImage, iconTrailing { icon(systemImage) }
        }
        .font(.system(size: small ? 15 : 17, weight: small ? .medium : .semibold))
        .padding(.horizontal, small ? 16 : 22)
        .frame(maxWidth: fill ? .infinity : nil)
        .frame(height: small ? 44 : 50)
        .contentShape(Capsule())
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: small ? 14 : 16, weight: .medium))
    }
}

/// A 44pt round button for close, back and more.
struct CircleButton: View {
    @Environment(\.theme) private var theme
    var systemImage: String
    var label: String
    var onImage = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(onImage ? Color.white : theme.inkColor)
                .frame(width: 44, height: 44)
                .background {
                    if onImage { Circle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark) }
                    else { Circle().fill(theme.controlColor) }
                }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Cover

/// The recipient's photo, or, without one, their initial set large on the raised surface.
struct CoverImage: View {
    @Environment(\.theme) private var theme
    var sendoff: Sendoff

    var body: some View {
        if let url = sendoff.recipientPhotoURL {
            // Fill whatever frame it is given, never more: a bare scaledToFill widens its parent.
            Color.clear
                .overlay(alignment: .coverFocus) { RemoteImage(url: url).scaledToFill() }
                .clipped()
        } else {
            GeometryReader { g in
                let side = min(g.size.width, g.size.height)
                ZStack {
                    theme.raisedPaperColor
                    Text(sendoff.recipientInitial)
                        .font(.system(size: side * (side < 100 ? 0.5 : 0.62), weight: .regular, design: .serif))
                        .foregroundStyle(theme.inkColor.opacity(side < 100 ? 0.5 : 0.07))
                }
                .frame(width: g.size.width, height: g.size.height)
            }
        }
    }
}

extension Alignment {
    /// Where a cover photo is cropped from when its frame is a different shape: centred across,
    /// and a quarter of the way down, where faces usually are. The web's `center 25%`.
    static let coverFocus = Alignment(horizontal: .center, vertical: .quarterDown)
}

extension VerticalAlignment {
    private enum QuarterDown: AlignmentID {
        static func defaultValue(in d: ViewDimensions) -> CGFloat { d.height * 0.25 }
    }
    static let quarterDown = VerticalAlignment(QuarterDown.self)
}

/// Darkens the bottom of a photo so white type reads on it.
struct Scrim: View {
    var from: Double = 0.35
    var to: Double = 0.8
    var body: some View {
        LinearGradient(stops: [.init(color: .black.opacity(0), location: from), .init(color: .black.opacity(to), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Entry

/// One contribution, read on its own, with nothing around it. Text is sized by its length.
struct EntryPage: View {
    @Environment(\.theme) private var theme
    var contribution: Contribution
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 14 : 24) {
            if !contribution.photos.isEmpty {
                PhotoPager(photos: contribution.photos)
                    .frame(height: compact ? 200 : 380)
            }
            if let video = contribution.video {
                VideoTile(media: video)
            }
            if let voice = contribution.voice {
                VoiceTile(media: voice, large: !compact)
            }
            if let body = contribution.body, contribution.hasText {
                Text(body)
                    .font(compact ? Typeface.body : Typeface.entry(length: body.count))
                    .lineSpacing(compact ? 2 : 4)
                    .foregroundStyle(theme.inkColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SignatureLine(contribution: contribution)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// "— Dan Okafor · Your manager, somehow"
struct SignatureLine: View {
    @Environment(\.theme) private var theme
    var contribution: Contribution

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Rectangle().fill(theme.faintInkColor).frame(width: 24, height: 1)
            (Text(contribution.authorName).font(Typeface.signature).foregroundColor(theme.inkColor)
             + Text(contribution.authorRelationship.map { $0.isEmpty ? "" : " · \($0)" } ?? "")
                .font(Typeface.body).foregroundColor(theme.faintInkColor))
        }
    }
}

/// Photos, one at a time, inset with rounded corners. Swipe between them.
struct PhotoPager: View {
    @Environment(\.theme) private var theme
    var photos: [Media]
    @State private var index = 0

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { i, m in
                Color.clear
                    .overlay(RemoteImage(url: m.url ?? m.localURL).scaledToFill())
                    .clipped()
                    .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .always : .never))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct RemoteImage: View {
    @Environment(\.theme) private var theme
    var url: URL?
    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: Motion.fade)) { phase in
            switch phase {
            case .success(let img): img.resizable()
            default:
                ZStack {
                    theme.controlColor
                    Image(systemName: "photo").foregroundStyle(theme.faintInkColor)
                }
            }
        }
    }
}

struct VoiceTile: View {
    @Environment(\.theme) private var theme
    var media: Media
    var large = true
    private let audio = ForegroundMedia.shared

    var body: some View {
        let playing = audio.isPlaying(media)
        VStack(alignment: .leading, spacing: large ? 22 : 12) {
            Waveform(progress: audio.isCurrent(media) ? audio.progress : 0)
                .frame(height: large ? 96 : 40)
            HStack(spacing: 14) {
                Button { audio.toggle(media) } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: large ? 20 : 15, weight: .semibold))
                        .foregroundStyle(theme.onSealColor)
                        .frame(width: large ? 60 : 44, height: large ? 60 : 44)
                        .background(theme.sealColor, in: Circle())
                }
                .buttonStyle(.pressable)
                .disabled(media.url == nil && media.localURL == nil)
                .accessibilityLabel(playing ? "Pause" : "Play voice note")
                Text(duration)
                    .font(Typeface.body.monospacedDigit())
                    .foregroundStyle(theme.mutedInkColor)
            }
            if let t = media.transcript {
                Text("\u{201C}\(t)\u{201D}")
                    .font(large ? Typeface.entry(length: t.count) : Typeface.body)
                    .lineSpacing(large ? 4 : 2)
                    .foregroundStyle(theme.inkColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // Turning the page, or closing the reveal, ends it.
        .onDisappear { if audio.isCurrent(media) { audio.stop() } }
    }

    private var duration: String {
        let s = Int(media.durationSeconds ?? 0)
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Deterministic bars, drawn in from the left as progress advances.
struct Waveform: View {
    @Environment(\.theme) private var theme
    var progress: Double
    var bars: Int = 44

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 11)
            let gap: CGFloat = 3
            let bw = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
            for i in 0..<bars {
                let amp = 0.18 + rng.next() * 0.82
                let h = size.height * amp
                let x = CGFloat(i) * (bw + gap)
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: bw, height: h)
                let played = Double(i) / Double(bars) < progress
                ctx.fill(Path(roundedRect: rect, cornerRadius: bw / 2),
                         with: .color(played ? theme.inkColor : theme.inkColor.opacity(0.28)))
            }
        }
        .animation(.linear(duration: 0.3), value: progress)
        .accessibilityHidden(true)
    }
}

struct VideoTile: View {
    @Environment(\.theme) private var theme
    var media: Media
    @State private var playing = false

    var body: some View {
        ZStack {
            RemoteImage(url: media.posterURL)
                .aspectRatio(4/5, contentMode: .fill)
                .clipped()
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            guard media.url != nil || media.localURL != nil else { return }
            ForegroundMedia.shared.videoStarted(media)
            playing = true
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Play video")
        .fullScreenCover(isPresented: $playing, onDismiss: { ForegroundMedia.shared.stop() }) {
            if let url = media.localURL ?? media.url { VideoScreen(url: url) }
        }
        .overlay(alignment: .bottomTrailing) {
            if let d = media.durationSeconds {
                Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60))
                    .font(Typeface.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(12)
            }
        }
    }
}
