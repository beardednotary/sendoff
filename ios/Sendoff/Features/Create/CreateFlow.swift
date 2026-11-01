import SwiftUI
import PhotosUI

/// Organizer creates a Sendoff. Target: under three minutes.
/// Who → Occasion → Look and music → When.
struct CreateFlow: View {
    @Environment(\.store) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(PurchaseManager.self) private var purchases
    var onCreated: (Sendoff) -> Void

    @State private var draft = SendoffDraft()
    @State private var step: Step = .who
    @State private var tracks: [MusicTrack] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var framing: PhotoToFrame?
    @State private var pickingSong = false
    @State private var saving = false
    @State private var error: String?

    enum Step: Int, CaseIterable { case who, occasion, look, when }

    private var first: String { draft.recipientName.isEmpty ? "they" : Sendoff.callName(draft.recipientName) }

    var body: some View {
        ZStack {
            Paper()
            VStack(spacing: 0) {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        switch step {
                        case .who: whoStep
                        case .occasion: occasionStep
                        case .look: lookStep
                        case .when: whenStep
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
                footer
            }
        }
        .tint(theme.inkColor)
        .alert("Couldn't create", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") {}
        } message: { Text(error ?? "") }
        .task { tracks = (try? await store.tracks()) ?? [] }
        .onChange(of: photoItem) { _, item in Task { await loadPhoto(item) } }
        .fullScreenCover(item: $framing) { f in
            PhotoFramer(image: f.image) { cropped in
                if let url = CoverPhoto.jpegFile(cropped) { draft.recipientPhoto = url }
                framing = nil
            } onCancel: {
                framing = nil
            }
            .appTheme()
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            if step == .who {
                CircleButton(systemImage: "xmark", label: "Cancel") { dismiss() }
            } else {
                CircleButton(systemImage: "chevron.left", label: "Back") { go(-1) }
            }
            Spacer()
            Text("\(step.rawValue + 1) of \(Step.allCases.count)").font(Typeface.caption).foregroundStyle(theme.faintInkColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { s in
                    Capsule().fill(s == step ? theme.inkColor : theme.controlColor)
                        .frame(width: s == step ? 18 : 6, height: 6)
                }
            }
            .animation(Motion.settle, value: step)
            .accessibilityHidden(true)
            Spacer()
            if step == .when {
                PrimaryButton(title: saving ? "Creating…" : "Create", systemImage: "envelope", fill: false) { Task { await create() } }
                    .disabled(saving || !draft.isValid)
            } else {
                Button { go(1) } label: {
                    PillLabel(title: "Next", systemImage: "arrow.right", fill: false, iconTrailing: true)
                        .foregroundStyle(theme.onSealColor)
                        .background(theme.sealColor, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(step == .who && !draft.isValid)
                .opacity(step == .who && !draft.isValid ? 0.4 : 1)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func go(_ delta: Int) {
        withAnimation(Motion.turn) { step = Step(rawValue: step.rawValue + delta) ?? step }
    }

    private func heading(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: eyebrow)
            Text(title)
                .font(Typeface.display(40)).displayTracking(40)
                .foregroundStyle(theme.inkColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Steps

    private var whoStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("New Sendoff", "Who are we\nsending off?")
            PhotosPicker(selection: $photoItem, matching: .images) {
                ZStack(alignment: .bottomLeading) {
                    if let url = draft.recipientPhoto {
                        Color.clear.overlay(alignment: .coverFocus) { RemoteImage(url: url).scaledToFill() }.clipped()
                    } else {
                        ZStack {
                            theme.raisedPaperColor
                            VStack(spacing: 8) {
                                Image(systemName: "person.crop.rectangle").font(.system(size: 28, weight: .light))
                                Text("Add a photo of them").font(Typeface.body)
                                Text("Optional. It goes on the cover.").font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                            }
                            .foregroundStyle(theme.mutedInkColor)
                        }
                    }
                    if draft.recipientPhoto != nil {
                        PillLabel(title: "Change photo", systemImage: "photo", fill: false, small: true)
                            .foregroundStyle(.white)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                            .padding(12)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 232)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(theme.ruleColor))
            }
            .buttonStyle(.pressable)
            .padding(.top, 26)

            VStack(spacing: 14) {
                Field(label: "Their name", text: $draft.recipientName, placeholder: "Maria Reyes").textContentType(.name)
                Field(label: "From (optional)", text: $draft.fromLine, placeholder: "The whole fourth floor")
                Field(label: "A line for the cover (optional)", text: $draft.coverMessage, placeholder: "Thirty-one years. We tried to fit it in here.", axis: .vertical)
            }
            .padding(.top, 22)
        }
    }

    private var occasionStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("The occasion", "What's the\noccasion?")
            VStack(spacing: 0) {
                ForEach(Occasion.allCases) { o in
                    Button {
                        draft.occasion = o
                        draft.themeID = o.defaultTheme
                        draft.musicTrackID = o.defaultTrack
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(o.title).font(Typeface.name).foregroundStyle(theme.inkColor)
                                if draft.occasion == o {
                                    Text(o.blurb).font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            Spacer()
                            if draft.occasion == o {
                                Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.inkColor)
                            }
                        }
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(draft.occasion == o ? .isSelected : [])
                    if o != Occasion.allCases.last { Rule() }
                }
            }
            .padding(.top, 18)
        }
    }

    /// Plus looks are free to try; this says what happens if nobody pays for one.
    private var plusLookNote: some View {
        let look = ThemeCatalog.theme(draft.themeID)
        let instead = ThemeCatalog.theme(draft.themeID.freeAlternative)
        let who = draft.recipientName.isEmpty ? "they" : Sendoff.callName(draft.recipientName)
        return Text("\(look.name) is free to try. Before it opens, add Sendoff Plus or get \(look.name) on its own, or \(who) will see \(instead.name).")
            .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
    }

    private var lookStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("How it looks", "Pick the look\nand the music.")

            Eyebrow(text: "Look").padding(.top, 30)
            VStack(spacing: 0) {
                ForEach(ThemeCatalog.all) { t in
                    choiceRow(selected: draft.themeID == t.id) { draft.themeID = t.id } content: {
                        ZStack {
                            Circle().fill(t.paperColor)
                            Seal(initial: draft.recipientName.isEmpty ? "A" : Sendoff.initial(of: draft.recipientName), size: 30).environment(\.theme, t)
                        }
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(theme.ruleColor))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(purchases.owns(t.id) ? t.name : "\(t.name) · Plus").font(Typeface.bodyStrong).foregroundStyle(theme.inkColor)
                            Text(t.tagline).font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                        }
                    }
                    if t.id != ThemeCatalog.all.last?.id { Rule() }
                }
            }
            if !purchases.owns(draft.themeID) { plusLookNote }

            Eyebrow(text: "Music when it opens").padding(.top, 30)
            VStack(spacing: 0) {
                songRow
                Rule()
                ForEach(tracks) { tr in
                    choiceRow(selected: draft.song == nil && draft.musicTrackID == tr.id) { draft.song = nil; draft.musicTrackID = tr.id } content: {
                        Image(systemName: "music.note").foregroundStyle(theme.faintInkColor).frame(width: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr.title).font(Typeface.bodyStrong).foregroundStyle(theme.inkColor)
                            Text([(tr.mood ?? "").capitalized, tr.durationSeconds.map { String(format: "%d:%02d", $0 / 60, $0 % 60) } ?? ""]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                        }
                    }
                    Rule()
                }
                choiceRow(selected: draft.song == nil && draft.musicTrackID == nil) { draft.song = nil; draft.musicTrackID = nil } content: {
                    Image(systemName: "speaker.slash").foregroundStyle(theme.faintInkColor).frame(width: 44)
                    Text("No music").font(Typeface.bodyStrong).foregroundStyle(theme.inkColor)
                }
            }
            if draft.song != nil {
                // The stock pick stays underneath as what plays if the Sendoff never gets Plus.
                Text("A song comes with Plus. Without it, they hear \(fallbackTrackName) instead.")
                    .font(Typeface.caption).foregroundStyle(theme.faintInkColor).padding(.top, 8)
            }
        }
        .sheet(isPresented: $pickingSong) {
            SongPicker { song in draft.song = song }.appTheme()
        }
    }

    /// Any song from Apple Music. Free to try, like the paid looks; the recipient hears it with Plus.
    private var songRow: some View {
        choiceRow(selected: draft.song != nil) { pickingSong = true } content: {
            Image(systemName: "music.note.list").foregroundStyle(theme.faintInkColor).frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.song?.title ?? "A song from Apple Music \u{00B7} Plus").font(Typeface.bodyStrong).foregroundStyle(theme.inkColor).lineLimit(1)
                Text(draft.song.map { "\($0.artist) \u{00B7} Change" } ?? "Any song you like")
                    .font(Typeface.caption).foregroundStyle(theme.faintInkColor).lineLimit(1)
            }
        }
    }

    private var fallbackTrackName: String {
        tracks.first { $0.id == draft.musicTrackID }?.title ?? "no music"
    }

    private func choiceRow<C: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> C) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                content()
                Spacer()
                if selected { Image(systemName: "checkmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(theme.inkColor) }
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var whenStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("When", "When does \(first)\nget to open it?")

            Picker("Reveal", selection: $draft.reveal) {
                ForEach(RevealPolicy.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.top, 26)

            VStack(spacing: 0) {
                if draft.reveal == .onDate {
                    DatePicker("Opens", selection: $draft.opensAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                        .onChange(of: draft.opensAt) { _, new in
                            if draft.closesAt >= new { draft.closesAt = Calendar.current.date(byAdding: .hour, value: -12, to: new) ?? new }
                        }
                        .padding(.vertical, 10)
                    Rule()
                }
                DatePicker("Stop collecting", selection: $draft.closesAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    .padding(.vertical, 10)
            }
            .font(Typeface.body).foregroundStyle(theme.inkColor)
            .padding(.top, 12)

            Eyebrow(text: "Entries").padding(.top, 28)
            VStack(spacing: 0) {
                ForEach(ModerationMode.allCases) { m in
                    choiceRow(selected: draft.moderation == m) { draft.moderation = m } content: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(m.title).font(Typeface.bodyStrong).foregroundStyle(theme.inkColor)
                            Text(m.detail).font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if m != ModerationMode.allCases.last { Rule() }
                }
            }

            Stepper(value: $draft.goal, in: 5...500, step: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aim for \(draft.goal) people").font(Typeface.bodyStrong).foregroundStyle(theme.inkColor)
                    Text("A target for you, not a limit.").font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                }
            }
            .padding(.top, 24)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "lock").foregroundStyle(theme.faintInkColor)
                Text("Every entry is private. People who add see only their own; you see all of them; \(first) sees them when it opens.")
                    .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            }
            .padding(.top, 24)
        }
    }

    // MARK: Actions

    /// A picked photo goes to the framer first; only the framed part is ever uploaded.
    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = CoverPhoto.image(from: data) else { return }
        // Cleared so picking the same photo again still reaches onChange.
        photoItem = nil
        framing = PhotoToFrame(image: image)
    }

    private func create() async {
        saving = true
        defer { saving = false }
        do {
            let s = try await store.create(draft)
            onCreated(s)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

#Preview {
    CreateFlow { _ in }.appTheme().environment(\.store, MockStore())
}
