import SwiftUI
import PhotosUI
import AVFoundation

/// A contributor adds to a Sendoff from the shared link. No account. Under two minutes.
struct ContributeFlow: View {
    @Environment(\.store) private var store
    @Environment(\.dismiss) private var dismiss
    var slug: String

    @State private var sendoff: Sendoff?
    @State private var existing: Contribution?
    @State private var draft = ContributionDraft()
    @State private var loadError: String?
    @State private var submitting = false
    @State private var done = false

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var recorder = VoiceRecorder()
    @State private var showRecorder = false

    var body: some View {
        Group {
            if let s = sendoff {
                content(s).sendoffTheme(ThemeCatalog.theme(s.themeID))
            } else if let loadError {
                VStack(spacing: 12) {
                    Text(loadError).font(Typeface.entry)
                    Button("Close") { dismiss() }
                }.padding()
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let s = try await store.sendoff(slug: slug)
                sendoff = s
                existing = try await store.myContribution(for: s.id)
            } catch { loadError = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func content(_ s: Sendoff) -> some View {
        let theme = ThemeCatalog.theme(s.themeID)
        ZStack {
            Paper()
            if done || existing != nil {
                thanks(s, theme)
            } else if !s.isCollecting {
                closed(s, theme)
            } else {
                VStack(spacing: 0) {
                    topBar(s, theme)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            header(s, theme)
                            promptChips(s, theme).padding(.top, 20)
                            editor(s, theme).padding(.top, 22)
                            attachments(theme).padding(.top, 16)
                            signature(theme).padding(.top, 26)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    PrimaryButton(title: submitting ? "Adding…" : "Add yours") { Task { await submit(s) } }
                        .disabled(!draft.isValid || submitting)
                        .opacity(draft.isValid ? 1 : 0.4)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
            }
        }
        .tint(theme.inkColor)
        .sheet(isPresented: $showRecorder) { VoiceRecorderSheet(recorder: recorder) { media in draft.media.append(media) }.sendoffTheme(theme) }
        .onChange(of: photoItems) { _, items in Task { await loadPhotos(items) } }
        .onChange(of: videoItem) { _, item in Task { await loadVideo(item) } }
    }

    // MARK: Sections

    private func topBar(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        ZStack {
            Seal(initial: s.recipientInitial, size: 40)
            HStack {
                CircleButton(systemImage: "xmark", label: "Close") { dismiss() }
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func header(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "For \(s.recipientName) · \(s.occasion.title)")
            Text("Write something\nonly \(s.recipientFirstName) will read.")
                .font(Typeface.display(40)).displayTracking(40)
                .foregroundStyle(theme.inkColor)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "lock").font(.system(size: 12))
                Text("Only \(s.recipientFirstName) and \(s.organizerName) will see this. Nobody else who adds can read it.\(s.closesAt.map { " Add yours by \($0.formatted(.dateTime.weekday(.wide).month(.wide).day()))." } ?? "")")
            }
            .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
            .padding(.top, 2)
        }
        .padding(.top, 18)
    }

    private func promptChips(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(s.occasion.prompts, id: \.self) { p in
                    Button {
                        draft.promptUsed = p
                        if draft.body.isEmpty { draft.body = p + "\n\n" }
                    } label: {
                        PillLabel(title: p, fill: false, small: true)
                            .foregroundStyle(draft.promptUsed == p ? theme.onSealColor : theme.inkColor)
                            .background(draft.promptUsed == p ? theme.sealColor : theme.controlColor, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    private func editor(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Start anywhere. A memory, a thank you, something you never said.", text: $draft.body, axis: .vertical)
                .font(Typeface.entry)
                .lineSpacing(6)
                .foregroundStyle(theme.inkColor)
                .lineLimit(4...30)
                .onChange(of: draft.body) { _, v in if v.count > Limits.bodyCharacters { draft.body = String(v.prefix(Limits.bodyCharacters)) } }
            Rule()
            if draft.body.count > Limits.bodyCharacters - 200 {
                Text("\(draft.body.count) / \(Limits.bodyCharacters)")
                    .font(Typeface.caption.monospacedDigit()).foregroundStyle(theme.faintInkColor)
            }
        }
    }

    private func attachments(_ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: Limits.photosPerEntry, matching: .images) {
                    attachLabel("Photo", "photo", theme)
                }
                Button { showRecorder = true } label: { attachLabel("Voice", "mic", theme) }
                    .disabled(draft.media.contains { $0.kind == .voice })
                PhotosPicker(selection: $videoItem, matching: .videos) {
                    attachLabel("Video", "video", theme)
                }
                .disabled(draft.media.contains { $0.kind == .video })
            }
            .buttonStyle(.pressable)
            ForEach(draft.media) { m in
                HStack(spacing: 12) {
                    Image(systemName: m.kind == .photo ? "photo" : m.kind == .voice ? "waveform" : "video")
                        .foregroundStyle(theme.faintInkColor).frame(width: 22)
                    Text(label(for: m)).font(Typeface.body).foregroundStyle(theme.inkColor)
                    Spacer()
                    Button { draft.media.removeAll { $0.id == m.id } } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.mutedInkColor)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Remove")
                }
            }
            Text("Video up to 60 seconds, voice up to 2 minutes, up to \(Limits.photosPerEntry) photos.")
                .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
        }
    }

    private func attachLabel(_ title: String, _ symbol: String, _ theme: SendoffTheme) -> some View {
        PillLabel(title: title, systemImage: symbol, fill: false, small: true)
            .foregroundStyle(theme.inkColor)
            .background(theme.controlColor, in: Capsule())
    }

    private func label(for m: Media) -> String {
        switch m.kind {
        case .photo: "Photo"
        case .voice: "Voice note · \(Int(m.durationSeconds ?? 0))s"
        case .video: "Video · \(Int(m.durationSeconds ?? 0))s"
        }
    }

    private func signature(_ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Field(label: "Sign it", text: $draft.authorName, placeholder: "Your name")
                .textContentType(.name)
            Field(label: "How you know them (optional)", text: $draft.authorRelationship, placeholder: "Your 2019 intern")
            Toggle(isOn: $draft.sharedWithGroup) {
                Text("Let the others who added read mine too").font(Typeface.body).foregroundStyle(theme.mutedInkColor)
            }
            .tint(theme.sealColor)
            .padding(.top, 4)
        }
    }

    private func thanks(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CircleButton(systemImage: "xmark", label: "Close") { dismiss() }
                Spacer()
            }
            Spacer()
            Seal(initial: s.recipientInitial, size: 96)
            Text("It's in the envelope.")
                .font(Typeface.display(40)).displayTracking(40)
                .foregroundStyle(theme.inkColor)
                .padding(.top, 28)
            Text("\(s.recipientFirstName) opens it \(s.opensAt.map { "on " + $0.formatted(.dateTime.weekday(.wide).month(.wide).day()) } ?? "when the time comes"). You can come back and change yours until then.")
                .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                .padding(.top, 12)
            Spacer()
            Spacer()
            Text("Know someone else leaving? Start a Sendoff of your own.")
                .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
        }
        .padding(20)
    }

    private func closed(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                CircleButton(systemImage: "xmark", label: "Close") { dismiss() }
                Spacer()
            }
            Spacer()
            Seal(initial: s.recipientInitial, size: 80)
            Text("This one's sealed.")
                .font(Typeface.display(40)).displayTracking(40)
                .foregroundStyle(theme.inkColor)
                .padding(.top, 28)
            Text("The Sendoff for \(s.recipientName) is no longer collecting.")
                .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                .padding(.top, 12)
            Spacer()
            Spacer()
        }
        .padding(20)
    }

    // MARK: Media loading

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        draft.media.removeAll { $0.kind == .photo }
        for item in items.prefix(Limits.photosPerEntry) {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                try? data.write(to: url)
                draft.media.append(Media(id: UUID(), kind: .photo, url: nil, posterURL: nil, durationSeconds: nil, transcript: nil, width: nil, height: nil, localURL: url))
            }
        }
    }

    private func loadVideo(_ item: PhotosPickerItem?) async {
        draft.media.removeAll { $0.kind == .video }
        guard let item, let movie = try? await item.loadTransferable(type: MovieFile.self) else { return }
        let asset = AVURLAsset(url: movie.url)
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        guard seconds <= Limits.videoSeconds + 1 else {
            videoItem = nil
            return
        }
        draft.media.append(Media(id: UUID(), kind: .video, url: nil, posterURL: nil, durationSeconds: seconds, transcript: nil, width: nil, height: nil, localURL: movie.url))
    }

    private func submit(_ s: Sendoff) async {
        submitting = true
        defer { submitting = false }
        if let c = try? await store.submit(draft, to: s.id) {
            existing = c
            withAnimation(Motion.fade) { done = true }
        }
    }
}

/// Moves a picked video into a temp file we own.
struct MovieFile: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return MovieFile(url: dest)
        }
    }
}

// MARK: - Voice recorder

@Observable
final class VoiceRecorder: NSObject, AVAudioRecorderDelegate {
    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    private(set) var fileURL: URL?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    func requestPermission() async -> Bool {
        if #available(iOS 17, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { c in AVAudioSession.sharedInstance().requestRecordPermission { c.resume(returning: $0) } }
        }
    }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self
        r.isMeteringEnabled = true
        r.record()
        recorder = r
        fileURL = url
        isRecording = true
        elapsed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            self.elapsed = r.currentTime
            self.level = max(0, (r.averagePower(forChannel: 0) + 50) / 50)
            if self.elapsed >= Limits.voiceSeconds { self.stop() }
        }
    }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func discard() {
        stop()
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        fileURL = nil
        elapsed = 0
    }
}

struct VoiceRecorderSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Bindable var recorder: VoiceRecorder
    var onSave: (Media) -> Void
    @State private var denied = false

    var body: some View {
        ZStack {
            Paper()
            VStack(spacing: 0) {
                Eyebrow(text: "Voice note")
                Text(recorder.isRecording ? "Recording" : recorder.fileURL == nil ? "Say it out loud" : "Got it")
                    .font(Typeface.display(40)).displayTracking(40)
                    .foregroundStyle(theme.inkColor)
                    .padding(.top, 10)
                Text(time).font(.system(size: 48, weight: .light).monospacedDigit()).foregroundStyle(theme.inkColor)
                    .padding(.top, 8)

                Spacer()
                Circle()
                    .fill(theme.controlColor)
                    .frame(width: 150 + CGFloat(recorder.level) * 70, height: 150 + CGFloat(recorder.level) * 70)
                    .overlay(
                        Button {
                            if recorder.isRecording { recorder.stop() } else { Task { await begin() } }
                        } label: {
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 30, weight: .semibold))
                                .foregroundStyle(theme.onSealColor)
                                .frame(width: 104, height: 104)
                                .background(theme.sealColor, in: Circle())
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
                    )
                    .animation(.easeOut(duration: 0.12), value: recorder.level)
                Spacer()

                Text("Up to two minutes. \(Int(Limits.voiceSeconds - recorder.elapsed))s left.")
                    .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                if denied {
                    Text("Microphone access is off. You can turn it on in Settings.").font(Typeface.caption).foregroundStyle(theme.inkColor)
                        .padding(.top, 8)
                }

                if !recorder.isRecording, let url = recorder.fileURL {
                    HStack(spacing: 10) {
                        SecondaryButton(title: "Again") { recorder.discard() }
                        PrimaryButton(title: "Use it") {
                            onSave(Media(id: UUID(), kind: .voice, url: nil, posterURL: nil, durationSeconds: recorder.elapsed, transcript: nil, width: nil, height: nil, localURL: url))
                            dismiss()
                        }
                    }
                    .padding(.top, 20)
                }
            }
            .padding(20)
            .padding(.top, 20)
        }
        .presentationDetents([.large])
        .onDisappear { if recorder.isRecording { recorder.stop() } }
    }

    private var time: String {
        let s = Int(recorder.elapsed)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func begin() async {
        guard await recorder.requestPermission() else { denied = true; return }
        try? recorder.start()
    }
}

#Preview {
    ContributeFlow(slug: "jo-moves").environment(\.store, MockStore())
}
