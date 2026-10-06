import SwiftUI

/// Organizer creates a Sendoff. Target: under three minutes.
/// Occasion → Who → Theme → Music → Reveal → Done.
struct CreateFlow: View {
    @Environment(\.store) private var store
    @Environment(\.dismiss) private var dismiss
    var onCreated: (Sendoff) -> Void

    @State private var draft = SendoffDraft()
    @State private var step: Step = .occasion
    @State private var tracks: [MusicTrack] = []
    @State private var saving = false
    @State private var error: String?

    enum Step: Int, CaseIterable { case occasion, who, theme, music, reveal }

    private var theme: SendoffTheme { ThemeCatalog.theme(draft.themeID) }

    var body: some View {
        NavigationStack {
            ZStack {
                Paper()
                VStack(spacing: 0) {
                    progress
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            switch step {
                            case .occasion: occasionStep
                            case .who: whoStep
                            case .theme: themeStep
                            case .music: musicStep
                            case .reveal: revealStep
                            }
                        }
                        .padding(20)
                        .padding(.bottom, 40)
                    }
                    footer
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(theme.mutedInkColor)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn't create", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") {}
            } message: { Text(error ?? "") }
        }
        .sendoffTheme(theme)
        .animation(Motion.fade, value: draft.themeID)
        .task { tracks = (try? await store.tracks()) ?? [] }
    }

    // MARK: Chrome

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= step.rawValue ? theme.sealColor : theme.ruleColor)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step != .occasion {
                QuietButton(title: "Back") { withAnimation(Motion.turn) { step = Step(rawValue: step.rawValue - 1) ?? .occasion } }
                    .frame(width: 110)
            }
            if step == .reveal {
                SealButton(title: saving ? "Sealing…" : "Create and get the link", systemImage: "envelope") { Task { await create() } }
                    .disabled(saving || !draft.isValid)
            } else {
                SealButton(title: "Next") { withAnimation(Motion.turn) { step = Step(rawValue: step.rawValue + 1) ?? .reveal } }
                    .disabled(step == .who && !draft.isValid)
            }
        }
        .padding(20)
        .background(theme.paperColor.opacity(0.96))
    }

    private func heading(_ title: String, _ sub: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typeface.title).foregroundStyle(theme.inkColor)
            if let sub { Text(sub).font(Typeface.ui).foregroundStyle(theme.mutedInkColor) }
        }
    }

    // MARK: Steps

    private var occasionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("What's the occasion?")
            VStack(spacing: 10) {
                ForEach(Occasion.allCases) { o in
                    Button {
                        draft.occasion = o
                        draft.themeID = o.defaultTheme
                        draft.musicTrackID = o.defaultTrack
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: o.symbol)
                                .font(.system(size: 18))
                                .frame(width: 30)
                                .foregroundStyle(draft.occasion == o ? theme.onSealColor : theme.mutedInkColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(o.title).font(Typeface.uiStrong)
                                Text(o.blurb).font(Typeface.caption).opacity(0.8)
                            }
                            .foregroundStyle(draft.occasion == o ? theme.onSealColor : theme.inkColor)
                            Spacer()
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                        .background(draft.occasion == o ? theme.sealColor : theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius + 4))
                        .overlay(RoundedRectangle(cornerRadius: theme.radius + 4).stroke(draft.occasion == o ? Color.clear : theme.ruleColor))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private var whoStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Who is it for?", "Their name goes on the envelope.")
            Field(label: "Name", text: $draft.recipientName, placeholder: "Maria Reyes")
                .textContentType(.name)
            Field(label: "From (optional)", text: $draft.fromLine, placeholder: "The whole fourth floor")
            Field(label: "A line for the cover (optional)", text: $draft.coverMessage, placeholder: "Thirty-one years. We tried to fit it in here.", axis: .vertical)
            if draft.isValid {
                Seal(initial: String(draft.recipientName.prefix(1)).uppercased(), size: 72)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    private var themeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Pick the paper", "Three included. More if you want them.")
            ForEach(ThemeCatalog.included) { t in themeCard(t) }
            Text("Premium").font(Typeface.stamp).kerning(1.1).foregroundStyle(theme.mutedInkColor).padding(.top, 8)
            ForEach(ThemeCatalog.premium) { t in themeCard(t) }
        }
    }

    private func themeCard(_ t: SendoffTheme) -> some View {
        Button { draft.themeID = t.id } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: t.radius).fill(t.paperColor)
                    Seal(initial: "A", size: 30).environment(\.theme, t)
                }
                .frame(width: 60, height: 60)
                .overlay(RoundedRectangle(cornerRadius: t.radius).stroke(Color.black.opacity(0.1)))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(t.name).font(Typeface.uiStrong).foregroundStyle(theme.inkColor)
                        if t.premium { Stamp(text: "Plus", tint: theme.sealColor) }
                    }
                    Text(t.tagline).font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                }
                Spacer()
                Image(systemName: draft.themeID == t.id ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(draft.themeID == t.id ? theme.sealColor : theme.ruleColor)
            }
            .padding(12)
            .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius + 4))
            .overlay(RoundedRectangle(cornerRadius: theme.radius + 4).stroke(draft.themeID == t.id ? theme.sealColor : theme.ruleColor))
        }
        .buttonStyle(.pressable)
    }

    private var musicStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            heading("Music for the reveal", "Plays when the seal breaks. Ducks under voice notes.")
            ForEach(tracks) { tr in
                Button { draft.musicTrackID = tr.id } label: {
                    HStack(spacing: 14) {
                        Image(systemName: draft.musicTrackID == tr.id ? "waveform" : "music.note")
                            .frame(width: 28)
                            .foregroundStyle(draft.musicTrackID == tr.id ? theme.sealColor : theme.mutedInkColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tr.title).font(Typeface.uiStrong).foregroundStyle(theme.inkColor)
                            Text((tr.mood ?? "").capitalized).font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                        }
                        Spacer()
                        if let d = tr.durationSeconds {
                            Text(String(format: "%d:%02d", d / 60, d % 60)).font(Typeface.caption.monospacedDigit()).foregroundStyle(theme.mutedInkColor)
                        }
                    }
                    .padding(14)
                    .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius + 4))
                    .overlay(RoundedRectangle(cornerRadius: theme.radius + 4).stroke(draft.musicTrackID == tr.id ? theme.sealColor : theme.ruleColor))
                }
                .buttonStyle(.pressable)
            }
            HStack(spacing: 10) {
                Image(systemName: "link").foregroundStyle(theme.mutedInkColor)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text("Link a song from Apple Music").font(Typeface.uiStrong).foregroundStyle(theme.inkColor)
                        Stamp(text: "Plus", tint: theme.sealColor)
                    }
                    Text("Full track for Apple Music subscribers, 30-second preview for everyone else.")
                        .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                }
            }
            .padding(14)
            .overlay(RoundedRectangle(cornerRadius: theme.radius + 4).strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3])).foregroundStyle(theme.ruleColor))
            Button { draft.musicTrackID = nil } label: {
                Text(draft.musicTrackID == nil ? "No music ✓" : "No music").font(Typeface.ui).foregroundStyle(theme.mutedInkColor)
            }
        }
    }

    private var revealStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            heading("When does \(draft.recipientName.split(separator: " ").first.map(String.init) ?? "it") get to open it?")

            Picker("Reveal", selection: $draft.reveal) {
                ForEach(RevealPolicy.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if draft.reveal == .onDate {
                DatePicker("Opens", selection: $draft.opensAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                    .font(Typeface.ui).foregroundStyle(theme.inkColor)
                    .onChange(of: draft.opensAt) { _, new in
                        if draft.closesAt >= new { draft.closesAt = Calendar.current.date(byAdding: .hour, value: -12, to: new) ?? new }
                    }
            }
            DatePicker("Stop collecting", selection: $draft.closesAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                .font(Typeface.ui).foregroundStyle(theme.inkColor)

            Rule()

            VStack(alignment: .leading, spacing: 12) {
                Text("Entries").font(Typeface.uiStrong).foregroundStyle(theme.inkColor)
                ForEach(ModerationMode.allCases) { m in
                    Button { draft.moderation = m } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: draft.moderation == m ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(draft.moderation == m ? theme.sealColor : theme.ruleColor)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.title).font(Typeface.uiStrong).foregroundStyle(theme.inkColor)
                                Text(m.detail).font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Rule()

            Stepper(value: $draft.goal, in: 5...500, step: 5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aim for \(draft.goal) people").font(Typeface.uiStrong).foregroundStyle(theme.inkColor)
                    Text("Just a target for you. Not a limit.").font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                }
            }
            .tint(theme.sealColor)

            Rule()

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock").foregroundStyle(theme.sealColor)
                Text("Every entry is private. Contributors see only their own. You see all of them. \(draft.recipientName.isEmpty ? "The recipient" : draft.recipientName.split(separator: " ").first.map(String.init) ?? "") sees them at the reveal. Nobody else, ever.")
                    .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            }
        }
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

/// A labeled text field on paper.
struct Field: View {
    @Environment(\.theme) private var theme
    var label: String
    @Binding var text: String
    var placeholder: String
    var axis: Axis = .horizontal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            TextField(placeholder, text: $text, axis: axis)
                .font(axis == .vertical ? Typeface.entry : Typeface.ui)
                .foregroundStyle(theme.inkColor)
                .lineLimit(axis == .vertical ? 2...6 : 1...1)
                .padding(12)
                .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius))
                .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.ruleColor))
        }
    }
}

#Preview {
    CreateFlow { _ in }.environment(\.store, MockStore())
}
