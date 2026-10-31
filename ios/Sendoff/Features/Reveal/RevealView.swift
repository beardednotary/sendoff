import SwiftUI
import AVFoundation

/// Loads a Sendoff from the recipient's link (slug + key) and shows the reveal. The entries
/// arrive only when the seal is broken and the server agrees it is due.
struct RevealLoader: View {
    @Environment(\.store) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    var slug: String
    @State private var sendoff: Sendoff?
    @State private var error: String?

    private var key: String { AppRouter.recipientKey(for: slug) ?? "" }

    var body: some View {
        Group {
            if let s = sendoff {
                RevealView(sendoff: s, contributions: [], preview: false) {
                    let opened = try await store.open(slug: slug, key: key)
                    return (opened, try await store.revealContributions(slug: slug, key: key))
                }
            } else if let error {
                ZStack {
                    Paper()
                    VStack(alignment: .leading, spacing: 12) {
                        Spacer()
                        Text(error).font(Typeface.display(40)).displayTracking(40).foregroundStyle(theme.inkColor)
                        Text("The Sendoff only opens with the link or QR code you were given. Ask the person who made it to send it again.")
                            .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                        Spacer()
                        SecondaryButton(title: "Close") { dismiss() }
                    }
                    .padding(20)
                }
            } else {
                ZStack { Paper(); ProgressView().tint(theme.faintInkColor) }
            }
        }
        .task {
            do { sendoff = try await store.reveal(slug: slug, key: key) }
            catch { self.error = error.localizedDescription }
        }
    }
}

/// The reveal. Sealed → hold the seal → cover → one entry at a time → kept.
struct RevealView: View {
    @Environment(\.store) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var sendoff: Sendoff
    var contributions: [Contribution]
    var preview: Bool
    /// Breaks the seal on the server and returns the entries. Nil for the organizer's preview,
    /// which already holds them.
    var open: (() async throws -> (Sendoff, [Contribution]))? = nil

    enum Stage: Equatable { case sealed, waiting, cover, entry(Int), kept }
    @State private var stage: Stage = .sealed
    @State private var hold: Double = 0
    @State private var holding = false
    @State private var opened = false
    @State private var player = MusicPlayer()
    @State private var dragX: CGFloat = 0
    @State private var trackTitle: String?
    @State private var loaded: [Contribution]?
    @State private var openError: String?

    private var theme: SendoffTheme { ThemeCatalog.theme(sendoff.themeID) }
    private var canOpen: Bool { preview || sendoff.isOpen || (sendoff.opensAt.map { $0 <= .now } ?? false) }
    private var hasPhoto: Bool { sendoff.recipientPhotoURL != nil }
    private var entries: [Contribution] { loaded ?? contributions }
    private var peopleCount: Int { loaded?.count ?? sendoff.contributorCount ?? contributions.count }

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
        }
        .overlay(alignment: .top) { chrome }
        .sendoffTheme(theme)
        .statusBarHidden()
        .onDisappear { player.stop() }
        .sensoryFeedback(.impact(weight: .heavy), trigger: opened)
        .task { trackTitle = try? await store.tracks().first { $0.id == sendoff.musicTrackID }?.title }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 10) {
            if case .entry(let i) = stage {
                HStack(spacing: 4) {
                    ForEach(0..<entries.count, id: \.self) { n in
                        Capsule().fill(n <= i ? theme.inkColor : theme.controlColor).frame(height: 2)
                    }
                }
                .animation(Motion.fade, value: stage)
            }
            HStack {
                if preview { Eyebrow(text: "Preview", tint: onImage ? .white.opacity(0.85) : nil) }
                else if case .entry(let i) = stage {
                    Text("\(i + 1) of \(entries.count)").font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                }
                Spacer()
                CircleButton(systemImage: "xmark", label: "Close", onImage: onImage) { player.stop(); dismiss() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
    }

    /// The close button sits on a photo during the sealed and cover stages.
    private var onImage: Bool {
        guard hasPhoto else { return false }
        switch stage {
        case .sealed, .waiting, .cover: return true
        default: return false
        }
    }

    // MARK: Stages

    /// The recipient's photo, out of focus behind the seal. Holding the seal draws its ring
    /// closed; at the end the blur lifts and the cover comes up.
    private var sealed: some View {
        ZStack {
            if hasPhoto {
                CoverImage(sendoff: sendoff)
                    .blur(radius: opened ? 0 : 40, opaque: true)
                    .ignoresSafeArea()
                Color.black.opacity(opened ? 0.1 : 0.5).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                Spacer()
                Seal(initial: sendoff.recipientInitial, size: 140, progress: hold, ink: ink)
                    .scaleEffect(holding ? 0.96 : 1)
                    .opacity(opened ? 0 : 1)
                    .animation(Motion.settle, value: holding)
                    .onLongPressGesture(minimumDuration: Motion.holdToOpen, maximumDistance: 40) {
                        breakSeal()
                    } onPressingChanged: { pressing in
                        guard canOpen else { if pressing { withAnimation(Motion.fade) { stage = .waiting } }; return }
                        holding = pressing
                        withAnimation(pressing ? .linear(duration: Motion.holdToOpen) : Motion.settle) { hold = pressing ? 1 : 0 }
                    }
                    .sensoryFeedback(.impact(weight: .light), trigger: holding) { _, new in new }
                    .accessibilityElement()
                    .accessibilityLabel("The seal, for \(sendoff.recipientName)")
                    .accessibilityHint(canOpen ? "Opens it" : "Not open yet")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { canOpen ? breakSeal() : withAnimation(Motion.fade) { stage = .waiting } }
                Text("For \(sendoff.recipientName)")
                    .font(Typeface.display(40)).displayTracking(40)
                    .foregroundStyle(ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 40)
                Text([sendoff.fromLine, peopleCount == 0 ? nil : "\(peopleCount) people"].compactMap { $0 }.joined(separator: " · "))
                    .font(Typeface.body).foregroundStyle(ink.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                Spacer()
                Text(openError ?? (holding ? "Keep holding" : canOpen ? "Press and hold the seal" : sendoff.statusLine))
                    .font(Typeface.body).foregroundStyle(ink.opacity(0.85))
                    .contentTransition(.opacity)
                    .animation(Motion.fade, value: holding)
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 28)
            .opacity(opened ? 0 : 1)
        }
    }

    /// Text on the sealed screen: white over a photo, the theme's ink without one.
    private var ink: Color { hasPhoto ? .white : theme.inkColor }

    private var waiting: some View {
        ZStack {
            if hasPhoto {
                CoverImage(sendoff: sendoff).blur(radius: 40, opaque: true).ignoresSafeArea()
                Color.black.opacity(0.55).ignoresSafeArea()
            }
            VStack(spacing: 0) {
                Spacer()
                Seal(initial: sendoff.recipientInitial, size: 110, ink: ink)
                Text("Not yet.")
                    .font(Typeface.display(40)).displayTracking(40).foregroundStyle(ink)
                    .padding(.top, 32)
                if let d = sendoff.opensAt {
                    Text("This opens \(d.formatted(.dateTime.weekday(.wide).month(.wide).day())). \(peopleCount) people are waiting for you.")
                        .font(Typeface.body).foregroundStyle(ink.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private var cover: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                if hasPhoto {
                    CoverImage(sendoff: sendoff)
                        .frame(width: g.size.width, height: g.size.height * 0.64)
                        .clipped()
                    LinearGradient(stops: [.init(color: theme.paperColor.opacity(0), location: 0.45), .init(color: theme.paperColor, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: g.size.height * 0.64)
                } else {
                    Seal(initial: sendoff.recipientInitial, size: 120)
                        .padding(.top, g.size.height * 0.2)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()
                    Eyebrow(text: sendoff.occasion.title, tint: theme.mutedInkColor)
                    Text(sendoff.recipientName)
                        .font(Typeface.display(48)).displayTracking(48)
                        .foregroundStyle(theme.inkColor)
                        .minimumScaleFactor(0.6).lineLimit(2)
                        .padding(.top, 8)
                    if let f = sendoff.fromLine {
                        Text(f).font(Typeface.body).foregroundStyle(theme.mutedInkColor).padding(.top, 6)
                    }
                    if let m = sendoff.coverMessage {
                        Text(m).font(Typeface.entry).lineSpacing(4).foregroundStyle(theme.inkColor)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 22)
                    }
                    HStack {
                        if let trackTitle {
                            Label(trackTitle, systemImage: "music.note").labelStyle(TightLabel())
                                .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                        }
                        Spacer()
                        Button { advance() } label: {
                            PillLabel(title: entries.isEmpty ? "Finish" : "Begin", systemImage: "arrow.right", fill: false, small: true, iconTrailing: true)
                                .foregroundStyle(theme.inkColor)
                                .background(theme.controlColor, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 20)
            }
        }
        .ignoresSafeArea(edges: .top)
        .contentShape(Rectangle())
        .gesture(pageGesture)
    }

    private func entry(_ i: Int) -> some View {
        GeometryReader { g in
            ScrollView {
                EntryPage(contribution: entries[i])
                    .offset(x: dragX * 0.25)
                    .opacity(1 - min(0.4, abs(dragX) / 600))
                    .padding(.horizontal, 20)
                    .padding(.top, 96)
                    .padding(.bottom, 48)
                    .frame(minHeight: g.size.height)
            }
            .scrollIndicators(.hidden)
        }
        .contentShape(Rectangle())
        .simultaneousGesture(pageGesture)
        .onTapGesture { advance() }
        .onAppear { if entries[i].voice != nil || entries[i].video != nil { player.duck() } else { player.unduck() } }
    }

    private var kept: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()
            Seal(initial: sendoff.recipientInitial, size: 96)
            Text("Kept for you.")
                .font(Typeface.display(48)).displayTracking(48).foregroundStyle(theme.inkColor)
                .padding(.top, 28)
            Text("\(peopleCount) people wrote to you. This stays here as long as you want it.")
                .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                .padding(.top, 12)
            Spacer()
            VStack(spacing: 10) {
                PrimaryButton(title: "Read it again", systemImage: "arrow.counterclockwise") {
                    withAnimation(Motion.turn) { stage = .cover }
                }
                SecondaryButton(title: "Save as PDF", systemImage: "doc") { /* ImageRenderer export, phase 2 */ }
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Behavior

    private func breakSeal() {
        guard canOpen, !opened else { return }
        holding = false
        openError = nil
        withAnimation(reduceMotion ? Motion.fade : .easeOut(duration: 0.7)) { opened = true }
        player.play(trackID: sendoff.musicTrackID)
        Task {
            async let pause: Void = Task.sleep(for: .milliseconds(reduceMotion ? 300 : 650))
            if let open {
                do {
                    loaded = try await open().1
                } catch {
                    player.stop()
                    withAnimation(Motion.settle) { opened = false; hold = 0 }
                    if case StoreError.sealed = error {
                        withAnimation(Motion.fade) { stage = .waiting }
                    } else {
                        openError = "That didn't go through. Check your connection and hold it again."
                    }
                    return
                }
            }
            try? await pause
            withAnimation(reduceMotion ? Motion.fade : Motion.lift) { stage = .cover }
        }
    }

    private func advance() {
        switch stage {
        case .cover: withAnimation(turnAnimation) { stage = entries.isEmpty ? .kept : .entry(0) }
        case .entry(let i): withAnimation(turnAnimation) { stage = i + 1 < entries.count ? .entry(i + 1) : .kept }
        default: break
        }
    }

    private func retreat() {
        switch stage {
        case .entry(let i): withAnimation(turnAnimation) { stage = i == 0 ? .cover : .entry(i - 1) }
        case .kept: withAnimation(turnAnimation) { stage = entries.isEmpty ? .cover : .entry(entries.count - 1) }
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
