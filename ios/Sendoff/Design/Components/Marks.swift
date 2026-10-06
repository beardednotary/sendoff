import SwiftUI

// The four marks of Sendoff: Seal, Flap, Stamp, Ribbon. Plus the paper they sit on.
// Nothing here is an illustration. Everything is geometry and type.

// MARK: - Paper

/// The page itself: theme paper with a faint texture so it never reads as flat UI.
struct Paper: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            theme.paperColor
            PaperGrain(texture: theme.texture)
                .blendMode(theme.isDark ? .plusLighter : .multiply)
                .opacity(theme.isDark ? 0.08 : 0.35)
        }
        .ignoresSafeArea()
    }
}

/// Cheap procedural texture. Deterministic so it does not shimmer between frames.
struct PaperGrain: View {
    var texture: PaperTexture

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 7)
            let count: Int
            let dot: CGFloat
            switch texture {
            case .paper: count = 1800; dot = 1.2
            case .linen: count = 900; dot = 1.6
            case .chalk: count = 2600; dot = 0.9
            case .grain: count = 3200; dot = 0.8
            case .grass: count = 1200; dot = 1.4
            }
            for _ in 0..<count {
                let x = CGFloat(rng.next()) * size.width
                let y = CGFloat(rng.next()) * size.height
                let a = 0.15 + rng.next() * 0.35
                let rect = CGRect(x: x, y: y, width: dot, height: texture == .linen ? dot * 3 : dot)
                ctx.fill(Path(ellipseIn: rect), with: .color(.black.opacity(a)))
            }
        }
        .allowsHitTesting(false)
    }
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

/// A wax seal: slightly irregular circle with the recipient's initial.
struct Seal: View {
    @Environment(\.theme) private var theme
    var initial: String
    var size: CGFloat = 88
    var cracked: Bool = false

    var body: some View {
        ZStack {
            SealShape()
                .fill(sealFill)
                .overlay(
                    SealShape()
                        .stroke(theme.onSealColor.opacity(0.18), lineWidth: 1)
                        .padding(size * 0.11)
                )
                .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.22), radius: size * 0.08, y: size * 0.05)

            Text(initial)
                .font(.system(size: size * 0.46, weight: .semibold, design: .serif))
                .foregroundStyle(theme.onSealColor)
                .offset(y: size * 0.01)

            if cracked {
                SealCrack()
                    .stroke(theme.onSealColor.opacity(0.7), style: StrokeStyle(lineWidth: max(1, size * 0.02), lineCap: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Seal with the letter \(initial)")
    }

    private var sealFill: AnyShapeStyle {
        if theme.foil {
            return AnyShapeStyle(
                LinearGradient(colors: [theme.sealColor, theme.sealColor.opacity(0.75), Color.white.opacity(0.6), theme.sealColor],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        }
        return AnyShapeStyle(
            RadialGradient(colors: [theme.sealColor.opacity(0.92), theme.sealColor],
                           center: .init(x: 0.38, y: 0.32), startRadius: 0, endRadius: size * 0.7)
        )
    }
}

/// A circle whose edge wobbles a little, like pressed wax.
struct SealShape: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        let steps = 72
        for i in 0...steps {
            let t = Double(i) / Double(steps) * .pi * 2
            let wobble = 1 + 0.028 * sin(t * 7 + 0.4) + 0.016 * cos(t * 11)
            let pt = CGPoint(x: c.x + cos(t) * r * wobble, y: c.y + sin(t) * r * wobble)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}

struct SealCrack: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.42))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.55))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.58, y: rect.minY + rect.height * 0.44))
        p.addLine(to: CGPoint(x: rect.minX + rect.width * 0.84, y: rect.minY + rect.height * 0.6))
        return p
    }
}

// MARK: - Flap

/// The envelope flap. A shallow triangle that lifts on its top edge.
struct Flap: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Stamp

/// Small caps inside a dashed border. Marks an occasion, a status or a signature.
struct Stamp: View {
    @Environment(\.theme) private var theme
    var text: String
    var tint: Color? = nil

    var body: some View {
        Text(text.uppercased())
            .font(Typeface.stamp)
            .kerning(1.1)
            .foregroundStyle(tint ?? theme.mutedInkColor)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                    .foregroundStyle((tint ?? theme.mutedInkColor).opacity(0.7))
            )
    }
}

// MARK: - Ribbon

/// A thin band that wraps a cover. Carries the count.
struct Ribbon: View {
    @Environment(\.theme) private var theme
    var text: String

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(Typeface.uiStrong)
                .foregroundStyle(theme.onSealColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(theme.sealColor)
            RibbonTail()
                .fill(theme.sealColor)
                .frame(width: 10)
        }
        .fixedSize()
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
    }
}

struct RibbonTail: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Rule

/// A hairline. Chalk themes get a slightly rough one.
struct Rule: View {
    @Environment(\.theme) private var theme
    var body: some View {
        Rectangle()
            .fill(theme.ruleColor)
            .frame(height: 1)
    }
}

// MARK: - Envelope

/// The sealed envelope shown to a recipient. Tap the seal to break it.
struct Envelope: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var sendoff: Sendoff
    var contributorCount: Int
    var opened: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = w * 0.72
            ZStack(alignment: .top) {
                // Body
                RoundedRectangle(cornerRadius: theme.radius)
                    .fill(theme.raisedPaperColor)
                    .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.ruleColor))
                    .frame(width: w, height: h)
                    .shadow(color: .black.opacity(theme.isDark ? 0.45 : 0.14), radius: 18, y: 10)

                // Address block
                VStack(spacing: 6) {
                    Text("To")
                        .font(Typeface.caption)
                        .foregroundStyle(theme.mutedInkColor)
                    Text(sendoff.recipientName)
                        .font(Typeface.display(min(34, w * 0.09)))
                        .foregroundStyle(theme.inkColor)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                    if let from = sendoff.fromLine {
                        Text(from)
                            .font(Typeface.signature)
                            .foregroundStyle(theme.mutedInkColor)
                    }
                }
                .frame(width: w * 0.8)
                .offset(y: h * 0.64)

                // Flap
                Flap()
                    .fill(theme.paperColor.opacity(0.98))
                    .overlay(Flap().stroke(theme.ruleColor))
                    .frame(width: w, height: h * 0.48)
                    .rotation3DEffect(
                        .degrees(opened ? -168 : 0),
                        axis: (x: 1, y: 0, z: 0),
                        anchor: .top,
                        perspective: 0.6
                    )
                    .zIndex(opened ? 0 : 2)
                    .shadow(color: .black.opacity(opened ? 0 : 0.12), radius: 6, y: 4)

                // Seal sits on the flap tip
                Seal(initial: sendoff.recipientInitial, size: w * 0.2, cracked: opened)
                    .offset(y: h * 0.48 - w * 0.1)
                    .scaleEffect(opened ? 0.85 : 1)
                    .opacity(opened ? 0 : 1)
                    .zIndex(3)

                // Ribbon with the count
                Ribbon(text: "\(contributorCount) people")
                    .rotationEffect(.degrees(-4))
                    .offset(x: -w * 0.33, y: h * 0.12)
                    .zIndex(4)
            }
            .frame(width: w, height: h)
            .animation(reduceMotion ? Motion.fade : Motion.lift, value: opened)
        }
        .aspectRatio(1 / 0.72, contentMode: .fit)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sealed envelope for \(sendoff.recipientName) from \(contributorCount) people")
    }
}

// MARK: - Buttons

/// The one important action on a screen. Seal colored, serif label.
struct SealButton: View {
    @Environment(\.theme) private var theme
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 18, weight: .semibold, design: .serif))
            .foregroundStyle(theme.onSealColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(theme.sealColor, in: RoundedRectangle(cornerRadius: theme.radius + 6))
        }
        .buttonStyle(.pressable)
    }
}

/// Everything that is not the one important action.
struct QuietButton: View {
    @Environment(\.theme) private var theme
    var title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Typeface.uiStrong)
            .foregroundStyle(theme.inkColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: theme.radius + 6).stroke(theme.inkColor.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.tap, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Entry card

/// One contribution, read on its own. Never in a grid in the reveal.
struct EntryPage: View {
    @Environment(\.theme) private var theme
    var contribution: Contribution

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if !contribution.photos.isEmpty {
                PhotoStack(photos: contribution.photos)
            }
            if let video = contribution.video {
                VideoTile(media: video)
            }
            if let voice = contribution.voice {
                VoiceTile(media: voice)
            }
            if let body = contribution.body, contribution.hasText {
                Text(body)
                    .font(Typeface.entry)
                    .lineSpacing(6)
                    .foregroundStyle(theme.inkColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Rectangle().fill(theme.sealColor).frame(width: 22, height: 2).offset(y: -4)
                Text(contribution.signature)
                    .font(Typeface.signature)
                    .foregroundStyle(theme.mutedInkColor)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius + 4))
        .overlay(RoundedRectangle(cornerRadius: theme.radius + 4).stroke(theme.ruleColor))
    }
}

/// Photos drop in with a tiny rotation that settles.
struct PhotoStack: View {
    @Environment(\.theme) private var theme
    var photos: [Media]

    var body: some View {
        ZStack {
            ForEach(Array(photos.prefix(3).enumerated()), id: \.element.id) { i, m in
                RemoteImage(url: m.url ?? m.localURL)
                    .aspectRatio(4/3, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .padding(6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    .rotationEffect(.degrees(Double(i - 1) * 2.2))
                    .offset(x: CGFloat(i - 1) * 6, y: CGFloat(i) * -4)
            }
        }
    }
}

struct RemoteImage: View {
    @Environment(\.theme) private var theme
    var url: URL?
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img): img.resizable()
            default:
                ZStack {
                    theme.accentColor
                    Image(systemName: "photo").foregroundStyle(theme.mutedInkColor)
                }
            }
        }
    }
}

struct VoiceTile: View {
    @Environment(\.theme) private var theme
    var media: Media
    @State private var playing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(theme.onSealColor)
                        .frame(width: 44, height: 44)
                        .background(theme.sealColor, in: Circle())
                }
                .buttonStyle(.pressable)
                Waveform(progress: playing ? 0.4 : 0)
                    .frame(height: 36)
                Text(duration)
                    .font(Typeface.caption.monospacedDigit())
                    .foregroundStyle(theme.mutedInkColor)
            }
            if let t = media.transcript {
                Text(t)
                    .font(Typeface.caption)
                    .foregroundStyle(theme.mutedInkColor)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .background(theme.accentColor.opacity(theme.isDark ? 0.5 : 0.35), in: RoundedRectangle(cornerRadius: theme.radius + 2))
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
    var bars: Int = 36

    var body: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: 11)
            let gap: CGFloat = 2.5
            let bw = (size.width - gap * CGFloat(bars - 1)) / CGFloat(bars)
            for i in 0..<bars {
                let amp = 0.25 + rng.next() * 0.75
                let h = size.height * amp
                let x = CGFloat(i) * (bw + gap)
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: bw, height: h)
                let played = Double(i) / Double(bars) < progress
                ctx.fill(Path(roundedRect: rect, cornerRadius: bw / 2),
                         with: .color(played ? theme.sealColor : theme.inkColor.opacity(0.35)))
            }
        }
        .animation(.linear(duration: 0.3), value: progress)
    }
}

struct VideoTile: View {
    @Environment(\.theme) private var theme
    var media: Media

    var body: some View {
        ZStack {
            RemoteImage(url: media.posterURL)
                .aspectRatio(16/9, contentMode: .fill)
                .clipped()
            Image(systemName: "play.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(theme.onSealColor)
                .frame(width: 60, height: 60)
                .background(theme.sealColor, in: Circle())
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radius + 2))
        .overlay(alignment: .bottomTrailing) {
            if let d = media.durationSeconds {
                Text(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60))
                    .font(Typeface.caption.monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: Capsule())
                    .padding(10)
            }
        }
    }
}
