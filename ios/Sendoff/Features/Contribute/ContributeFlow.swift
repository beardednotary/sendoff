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
        NavigationStack {
            ZStack {
                Paper()
                if done || existing != nil {
                    thanks(s, theme)
                } else if !s.isCollecting {
                    closed(s, theme)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            header(s, theme)
                            promptChips(s, theme)
                            editor(theme)
                            attachments(s, theme)
                            signature(theme)
                            privacy(s, theme)
                        }
                        .padding(20)
                        .padding(.bottom, 100)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.foregroundStyle(theme.mutedInkColor) }
            }
            .safeAreaInset(edge: .bottom) {
                if s.isCollecting && !done && existing == nil {
                    SealButton(title: submitting ? "Adding…" : "Add yours", systemImage: "envelope") { Task { await submit(s) } }
                        .disabled(!draft.isValid || submitting)
                        .padding(20)
                        .background(theme.paperColor.opacity(0.96))
                }
            }
            .sheet(isPresented: $showRecorder) { VoiceRecorderSheet(recorder: recorder) { media in draft.media.append(media) } }
            .onChange(of: photoItems) { _, items in Task { await loadPhotos(items) } }
            .onChange(of: videoItem) { _, item in Task { await loadVideo(item) } }
        }
    }

    // MARK: Sections

    private func header(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Stamp(text: s.occasion.title)
                    Text("For \(s.recipientName)")
                        .font(Typeface.display(32)).foregroundStyle(theme.inkColor)
                    if let f = s.fromLine { Text(f).font(Typeface.signature).foregroundStyle(theme.mutedInkColor) }
                }
                Spacer()
                Seal(initial: s.recipientInitial, size: 56)
            }
            if let c = s.closesAt {
                Text("Add yours by \(c.formatted(.dateTime.weekday(.wide).month(.wide).day()))")
                    .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            }
            Rule()
        }
    }

    private func promptChips(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Not sure where to start?").font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(s.occasion.prompts, id: \.self) { p in
                        Button {
                            draft.promptUsed = p
                            if draft.body.isEmpty { draft.body = p + "\n\n" }
                        } label: {
                            Text(p)
                                .font(Typeface.caption)
                                .foregroundStyle(draft.promptUsed == p ? theme.onSealColor : theme.inkColor)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(draft.promptUsed == p ? theme.sealColor : theme.raisedPaperColor, in: Capsule())
                                .overlay(Capsule().stroke(draft.promptUsed == p ? Color.clear : theme.ruleColor))
                        }
                        .buttonStyle(.pressable)
                    }
                }
            }
        }
    }

    private func editor(_ theme: SendoffTheme) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Write something only \(sendoff?.recipientFirstName ?? "they") will read…", text: $draft.body, axis: .vertical)
                .font(Typeface.entry)
                .lineSpacing(5)
                .foregroundStyle(theme.inkColor)
                .lineLimit(5...20)
                .padding(16)
                .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius + 2))
                .overlay(RoundedRectangle(cornerRadius: theme.radius + 2).stroke(theme.ruleColor))
                .onChange(of: draft.body) { _, v in if v.count > Limits.bodyCharacters { draft.body = String(v.prefix(Limits.bodyCharacters)) } }
            Text("\(draft.body.count) / \(Limits.bodyCharacters)")
                .font(Typeface.caption.monospacedDigit()).foregroundStyle(theme.mutedInkColor.opacity(0.7))
        }
    }

    private func attachments(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to it").font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            HStack(spacing: 10) {
                PhotosPicker(selection: $photoItems, maxSelectionCount: Limits.photosPerEntry, matching: .images) {
                    attachButton("Photos", "photo.on.rectangle", theme)
                }
                Button { showRecorder = true } label: { attachButton("Voice", "waveform", theme) }
                    .disabled(draft.media.contains { $0.kind == .voice })
                PhotosPicker(selection: $videoItem, matching: .videos) {
                    attachButton("Video", "video", theme)
                }
                .disabled(draft.media.contains { $0.kind == .video })
            }
            if !draft.media.isEmpty {
                VStack(spacing: 8) {
                    ForEach(draft.media) { m in
                        HStack(spacing: 12) {
                            Image(systemName: m.kind == .photo ? "photo" : m.kind == .voice ? "waveform" : "video")
                                .foregroundStyle(theme.sealColor).frame(width: 24)
                            Text(label(for: m)).font(Typeface.ui).foregroundStyle(theme.inkColor)
                            Spacer()
                            Button { draft.media.removeAll { $0.id == m.id } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(theme.mutedInkColor)
                            }
                        }
                        .padding(12)
                        .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius))
                    }
                }
            }
            Text("Video up to 60 seconds, voice up to 2 minutes, up to \(Limits.photosPerEntry) photos.")
                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor.opacity(0.8))
        }
    }

    private func attachButton(_ title: String, _ symbol: String, _ theme: SendoffTheme) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20))
            Text(title).font(Typeface.caption)
        }
        .foregroundStyle(theme.inkColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius + 2))
        .overlay(RoundedRectangle(cornerRadius: theme.radius + 2).stroke(theme.ruleColor))
    }

    private func label(for m: Media) -> String {
        switch m.kind {
        case .photo: "Photo"
        case .voice: "Voice note · \(Int(m.durationSeconds ?? 0))s"
        case .video: "Video · \(Int(m.durationSeconds ?? 0))s"
        }
    }

    private func signature(_ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Rule()
            Field(label: "Sign it", text: $draft.authorName, placeholder: "Your name")
                .textContentType(.name)
            Field(label: "How you know them (optional)", text: $draft.authorRelationship, placeholder: "Your 2019 intern")
        }
    }

    private func privacy(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill").foregroundStyle(theme.sealColor)
                Text("Only \(s.recipientFirstName) and \(s.organizerName) will see this. Nobody else who adds to this Sendoff can read it.")
                    .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            }
            Toggle(isOn: $draft.sharedWithGroup) {
                Text("Let the others who added read mine too").font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            }
            .tint(theme.sealColor)
        }
    }

    private func thanks(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Seal(initial: s.recipientInitial, size: 96)
            Text("It's in the envelope.").font(Typeface.title).foregroundStyle(theme.inkColor)
            Text("\(s.recipientFirstName) opens it \(s.opensAt.map { "on " + $0.formatted(.dateTime.weekday(.wide).month(.wide).day()) } ?? "when the time comes"). You can come back and change yours until then.")
                .font(Typeface.ui).foregroundStyle(theme.mutedInkColor).multilineTextAlignment(.center)
            Spacer()
            Text("Know someone else leaving? Start a Sendoff of your own.")
                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor.opacity(0.8))
        }
        .padding(28)
    }

    private func closed(_ s: Sendoff, _ theme: SendoffTheme) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Seal(initial: s.recipientInitial, size: 80)
            Text("This one's sealed.").font(Typeface.title).foregroundStyle(theme.inkColor)
            Text("The Sendoff for \(s.recipientName) is no longer collecting.").font(Typeface.ui).foregroundStyle(theme.mutedInkColor).multilineTextAlignment(.center)
            Spacer()
        }.padding(28)
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
            VStack(spacing: 28) {
                Stamp(text: "Voice note")
                Text(recorder.isRecording ? "Recording" : recorder.fileURL == nil ? "Say it out loud" : "Got it")
                    .font(Typeface.title).foregroundStyle(theme.inkColor)
                Text(time).font(.system(size: 44, weight: .light, design: .serif).monospacedDigit()).foregroundStyle(theme.inkColor)

                Circle()
                    .fill(theme.sealColor.opacity(0.18))
                    .frame(width: 160 + CGFloat(recorder.level) * 60, height: 160 + CGFloat(recorder.level) * 60)
                    .overlay(
                        Button {
                            if recorder.isRecording { recorder.stop() } else { Task { await begin() } }
                        } label: {
                            Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(theme.onSealColor)
                                .frame(width: 110, height: 110)
                                .background(theme.sealColor, in: Circle())
                        }
                        .buttonStyle(.pressable)
                    )
                    .animation(.easeOut(duration: 0.12), value: recorder.level)

                Text("Up to two minutes. \(Int(Limits.voiceSeconds - recorder.elapsed))s left.")
                    .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)

                if denied {
                    Text("Microphone access is off. You can turn it on in Settings.").font(Typeface.caption).foregroundStyle(theme.sealColor)
                }

                Spacer()

                if !recorder.isRecording, let url = recorder.fileURL {
                    HStack(spacing: 12) {
                        QuietButton(title: "Again") { recorder.discard() }
                        SealButton(title: "Use it") {
                            onSave(Media(id: UUID(), kind: .voice, url: nil, posterURL: nil, durationSeconds: recorder.elapsed, transcript: nil, width: nil, height: nil, localURL: url))
                            dismiss()
                        }
                    }
                }
            }
            .padding(28)
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
