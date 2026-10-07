import SwiftUI
import AVFoundation

/// Loads a Sendoff from a recipient link and shows the reveal.
struct RevealLoader: View {
    @Environment(\.store) private var store
    @Environment(\.dismiss) private var dismiss
    var slug: String
    @State private var sendoff: Sendoff?
    @State private var contributions: [Contribution] = []
    @State private var error: String?

    var body: some View {
        Group {
            if let s = sendoff {
                RevealView(sendoff: s, contributions: contributions, preview: false)
            } else if let error {
                VStack(spacing: 12) { Text(error).font(Typeface.entry); Button("Close") { dismiss() } }.padding()
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let s = try await store.sendoff(slug: slug)
                contributions = try await store.revealContributions(for: s.id)
                sendoff = s
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// The reveal. Sealed envelope → cover → one entry at a time → kept.
struct RevealView: View {
    @Environment(\.store) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var sendoff: Sendoff
    var contributions: [Contribution]
    var preview: Bool

    enum Stage: Equatable { case sealed, waiting, cover, entry(Int), kept }
    @State private var stage: Stage = .sealed
    @State private var opened = false
    @State private var player = MusicPlayer()
    @State private var dragX: CGFloat = 0

    private var theme: SendoffTheme { ThemeCatalog.theme(sendoff.themeID) }
    private var canOpen: Bool { preview || sendoff.isOpen || (sendoff.opensAt.map { $0 <= .now } ?? false) }

    var body: some View {
        ZStack {
            Paper()
            switch stage {
            case .sealed: sealed
            case .waiting: waiting
            case .cover: cover.transition(pageTransition)
            case .entry(let i): entry(i).transition(pageTransition)
            case .kept: kept.transition(.opacity)
            }
            VStack {
                HStack {
                    if preview { Stamp(text: "Preview") }
                    Spacer()
                    Button { player.stop(); dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.inkColor).frame(width: 36, height: 36)
                            .background(theme.raisedPaperColor, in: Circle())
                    }
                }
                .padding(20)
                Spacer()
                if case .entry = stage { progressDots }
            }
        }
        .sendoffTheme(theme)
        .statusBarHidden()
        .onDisappear { player.stop() }
    }

    // MARK: Stages

    private var sealed: some View {
        VStack(spacing: 30) {
            Spacer()
            Envelope(sendoff: sendoff, contributorCount: contributions.count, opened: opened)
                .padding(.horizontal, 28)
                .onTapGesture { breakSeal() }
            VStack(spacing: 8) {
                Text(canOpen ? "Tap the seal" : sendoff.statusLine)
                    .font(Typeface.ui).foregroundStyle(theme.mutedInkColor)
                if !canOpen, let d = sendoff.opensAt {
                    Text("Sealed until \(d.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))")
                        .font(Typeface.caption).foregroundStyle(theme.mutedInkColor.opacity(0.8))
                }
            }
            Spacer()
            Spacer()
        }
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            Spacer()
            Seal(initial: sendoff.recipientInitial, size: 96)
            Text("Not yet.").font(Typeface.title).foregroundStyle(theme.inkColor)
            if let d = sendoff.opensAt {
                Text("This opens \(d.formatted(.dateTime.weekday(.wide).month(.wide).day())). \(contributions.count) people are waiting for you.")
                    .font(Typeface.ui).foregroundStyle(theme.mutedInkColor).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(28)
    }

    private var cover: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Stamp(text: sendoff.occasion.title)
            Text(sendoff.recipientName)
                .font(Typeface.display(52)).foregroundStyle(theme.inkColor)
                .minimumScaleFactor(0.6).lineLimit(2)
            if let f = sendoff.fromLine { Text(f).font(Typeface.signature).foregroundStyle(theme.mutedInkColor) }
            if let m = sendoff.coverMessage {
                Rule().padding(.vertical, 6)
                Text(m).font(Typeface.entry).lineSpacing(5).foregroundStyle(theme.inkColor)
            }
            Spacer()
            HStack {
                Ribbon(text: "\(contributions.count) people")
                Spacer()
                Text("Swipe to begin").font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            }
            .padding(.bottom, 30)
        }
        .padding(28)
        .contentShape(Rectangle())
        .gesture(pageGesture)
        .onTapGesture { advance() }
    }

    private func entry(_ i: Int) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 70)
                EntryPage(contribution: contributions[i])
                    .rotation3DEffect(.degrees(Double(dragX / 30)), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
                    .offset(x: dragX * 0.3)
                Text("\(i + 1) of \(contributions.count)").font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                Spacer(minLength: 60)
            }
            .padding(.horizontal, 20)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(pageGesture)
    }

    private var kept: some View {
        VStack(spacing: 20) {
            Spacer()
            PathMark(size: 84)
            Text("Kept for you.").font(Typeface.display(40)).foregroundStyle(theme.inkColor)
            Text("\(contributions.count) people. This stays here as long as you want it.")
                .font(Typeface.ui).foregroundStyle(theme.mutedInkColor).multilineTextAlignment(.center)
            Spacer()
            VStack(spacing: 10) {
                SealButton(title: "Read it again", systemImage: "arrow.counterclockwise") {
                    withAnimation(Motion.turn) { stage = .cover }
                }
                QuietButton(title: "Save as PDF", systemImage: "doc") { /* ImageRenderer export, phase 2 */ }
            }
        }
        .padding(28)
    }

    private var progressDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<contributions.count, id: \.self) { i in
                Capsule()
                    .fill({ if case .entry(let c) = stage, c == i { return theme.sealColor } ; return theme.ruleColor }())
                    .frame(width: { if case .entry(let c) = stage, c == i { return 18 } ; return 6 }(), height: 4)
            }
        }
        .padding(.bottom, 24)
        .animation(Motion.fade, value: stage)
    }

    // MARK: Behavior

    private func breakSeal() {
        guard canOpen else { withAnimation(Motion.fade) { stage = .waiting }; return }
        withAnimation(reduceMotion ? Motion.fade : Motion.lift) { opened = true }
        if !preview, !sendoff.isOpen { Task { try? await store.markOpened(sendoff.id) } }
        player.play(trackID: sendoff.musicTrackID)
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(Motion.turn) { stage = .cover }
        }
    }

    private func advance() {
        switch stage {
        case .cover: withAnimation(turnAnimation) { stage = contributions.isEmpty ? .kept : .entry(0) }
        case .entry(let i): withAnimation(turnAnimation) { stage = i + 1 < contributions.count ? .entry(i + 1) : .kept }
        default: break
        }
    }

    private func retreat() {
        switch stage {
        case .entry(let i): withAnimation(turnAnimation) { stage = i == 0 ? .cover : .entry(i - 1) }
        case .kept: withAnimation(turnAnimation) { stage = contributions.isEmpty ? .cover : .entry(contributions.count - 1) }
        default: break
        }
    }

    private var pageGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { v in dragX = v.translation.width }
            .onEnded { v in
                let w = v.translation.width
                withAnimation(Motion.settle) { dragX = 0 }
                if w < -60 { advance() } else if w > 60 { retreat() }
            }
    }

    private var turnAnimation: Animation {
        if reduceMotion { return Motion.fade }
        return theme.motion == .fade ? Motion.fade : Motion.turn
    }

    private var pageTransition: AnyTransition {
        if reduceMotion || theme.motion == .fade { return .opacity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }
}

// MARK: - Music

/// Plays the Sendoff's track and ducks under voice and video.
@Observable
final class MusicPlayer {
    private var player: AVPlayer?
    private(set) var isPlaying = false

    func play(trackID: String?) {
        guard let trackID, let url = Self.url(for: trackID) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: url)
        p.volume = 0
        p.play()
        player = p
        isPlaying = true
        fade(to: 0.8, over: 1.5)
    }

    func duck() { fade(to: 0.2, over: 0.4) }
    func unduck() { fade(to: 0.8, over: 1.5) }

    func stop() {
        fade(to: 0, over: 0.6)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            player?.pause(); player = nil; isPlaying = false
        }
    }

    private func fade(to target: Float, over seconds: Double) {
        guard let p = player else { return }
        let steps = 20
        let start = p.volume
        Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(for: .milliseconds(Int(seconds * 1000) / steps))
                p.volume = start + (target - start) * Float(i) / Float(steps)
            }
        }
    }

    /// Stock tracks are bundled as `{id}.m4a`; a remote URL is used when the bundle lacks one.
    static func url(for trackID: String) -> URL? {
        if let u = Bundle.main.url(forResource: trackID, withExtension: "m4a") { return u }
        return AppConfig.musicBaseURL?.appending(path: "\(trackID).m4a")
    }
}

#Preview("Open") {
    RevealView(sendoff: MockStore.sampleSendoff,
               contributions: MockStore.sampleContributions(for: MockStore.sampleSendoff.id),
               preview: true)
    .environment(\.store, MockStore())
}

#Preview("Sealed") {
    RevealView(sendoff: MockStore.sampleSealed, contributions: [], preview: false)
        .environment(\.store, MockStore())
}
