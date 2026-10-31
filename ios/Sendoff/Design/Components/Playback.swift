import AVFoundation
import AVKit
import SwiftUI

/// Voice notes and videos in entries, as on the web (web/app/src/lib/audio.ts): one plays at a
/// time, starting one stops the other, and the reveal's music ducks under it while it plays.
@Observable
final class ForegroundMedia {
    static let shared = ForegroundMedia()

    /// The voice note or video playing now, or paused part way through.
    private(set) var current: UUID?
    private(set) var paused = false
    /// How far through the current voice note, 0 to 1, for its waveform.
    private(set) var progress: Double = 0
    /// Set by the reveal so its music ducks under voice and video. The App Clip has no music.
    var duck: (() -> Void)?
    var unduck: (() -> Void)?

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    func isCurrent(_ media: Media) -> Bool { current == media.id }
    func isPlaying(_ media: Media) -> Bool { current == media.id && !paused }

    /// Plays a voice note from the start, or pauses and resumes the one already under way.
    func toggle(_ media: Media) {
        if current == media.id, let player {
            if paused { duck?(); player.play() } else { player.pause(); unduck?() }
            paused.toggle()
            return
        }
        guard let url = media.localURL ?? media.url else { return }
        stop()
        Self.activateSession()
        let p = AVPlayer(url: url)
        let fallback = media.durationSeconds ?? 0
        timeObserver = p.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 20), queue: .main) { [weak self, weak p] t in
            guard let self, let item = p?.currentItem else { return }
            let total = item.duration.seconds.isFinite ? item.duration.seconds : fallback
            if total > 0 { self.progress = min(1, t.seconds / total) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: p.currentItem, queue: .main) { [weak self] _ in
            self?.stop()
        }
        player = p
        current = media.id
        progress = 0
        duck?()
        p.play()
    }

    /// A video takes the whole screen: any voice note stops and the music ducks until it closes.
    func videoStarted(_ media: Media) {
        stop()
        Self.activateSession()
        current = media.id
        duck?()
    }

    func stop() {
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        player?.pause()
        player = nil
        if current != nil, !paused { unduck?() }
        current = nil
        paused = false
        progress = 0
    }

    /// `.playback` so a voice note is heard with the ring switch on silent, like any audio app.
    static func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }
}

/// A video from an entry, full screen with the system controls, playing as soon as it opens.
struct VideoScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        VideoPlayer(player: player)
            .ignoresSafeArea()
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                CircleButton(systemImage: "xmark", label: "Close", onImage: true) { dismiss() }
                    .padding(.leading, 16)
                    .padding(.top, 8)
            }
            .onAppear { player.play() }
            .onDisappear { player.pause() }
    }
}
