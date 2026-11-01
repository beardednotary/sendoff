import SwiftUI
import PhotosUI

/// The organizer tends a Sendoff: share, watch entries arrive, review, reorder, seal, open.
struct SendoffDetailView: View {
    @Environment(\.store) private var store
    @Environment(\.theme) private var theme
    @Environment(PurchaseManager.self) private var purchases
    var sendoffID: UUID

    @State private var sendoff: Sendoff?
    @State private var contributions: [Contribution] = []
    @State private var showShare = false
    @State private var showPreview = false
    @State private var showPaywall = false
    @State private var showReorder = false
    @State private var confirmOpen = false
    @State private var pickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var framing: PhotoToFrame?
    @State private var coverError: String?

    var body: some View {
        if let s = sendoff {
            ZStack {
                Paper()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        cover(s)
                        VStack(alignment: .leading, spacing: 0) {
                            facts(s)
                            actions(s).padding(.top, 24)
                            if !purchases.covers(s) {
                                lookLine(s).padding(.top, 18)
                            } else if s.plan == .free, !contributions.isEmpty {
                                keepLine(s).padding(.top, 18)
                            }
                            if s.moderation == .review, !pending.isEmpty { review }
                            envelope(s)
                            if !hidden.isEmpty { hiddenSection }
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 48)
                }
                .ignoresSafeArea(edges: .top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(s.recipientPhotoURL != nil ? .dark : nil, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) { menu(s) }
            }
            .sheet(isPresented: $showShare) { ShareView(sendoff: s).appTheme() }
            .sheet(isPresented: $showPaywall) {
                PaywallView(sendoff: s, entryCount: approved.count) { updated in sendoff = updated }.appTheme()
            }
            .sheet(isPresented: $showReorder) {
                ReorderSheet(entries: approved) { ids in
                    Task { try? await store.reorder(s.id, orderedIDs: ids); await load() }
                }
                .appTheme()
            }
            .fullScreenCover(isPresented: $showPreview) {
                RevealView(sendoff: previewSendoff(s), contributions: approved, preview: true)
            }
            .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = CoverPhoto.image(from: data) {
                        framing = PhotoToFrame(image: image)
                    }
                }
            }
            .fullScreenCover(item: $framing) { f in
                PhotoFramer(image: f.image) { cropped in
                    framing = nil
                    Task { await saveCover(cropped, for: s.id) }
                } onCancel: {
                    framing = nil
                }
                .appTheme()
            }
            .alert("Couldn't change the photo", isPresented: Binding(get: { coverError != nil }, set: { if !$0 { coverError = nil } })) {
                Button("OK") {}
            } message: { Text(coverError ?? "") }
            .confirmationDialog("Open it now?", isPresented: $confirmOpen, titleVisibility: .visible) {
                if purchases.covers(s) {
                    Button("Open for \(s.recipientFirstName)") { Task { await setState(.open) } }
                } else {
                    Button("Keep \(lookName(s.themeID))") { showPaywall = true }
                    Button("Open with \(lookName(s.themeID.freeAlternative))") { Task { await setState(.open) } }
                }
            } message: {
                if purchases.covers(s) {
                    Text("\(s.recipientFirstName) will be able to open it right away. Entries stop here.")
                } else {
                    Text("\(s.recipientFirstName) will be able to open it right away. \(lookName(s.themeID)) is a Plus look, so without Plus or \(lookName(s.themeID)) on its own, \(s.recipientFirstName) sees \(lookName(s.themeID.freeAlternative)).")
                }
            }
            .task { await load() }
            .refreshable { await load() }
        } else {
            ZStack { Paper(); ProgressView().tint(theme.faintInkColor) }
                .task { await load() }
        }
    }

    // MARK: Pieces

    private func cover(_ s: Sendoff) -> some View {
        let hasPhoto = s.recipientPhotoURL != nil
        return ZStack(alignment: .bottomLeading) {
            CoverImage(sendoff: s)
                .frame(maxWidth: .infinity)
                .containerRelativeFrame(.vertical) { h, _ in h * 0.5 }
                .clipped()
            LinearGradient(stops: [
                .init(color: .black.opacity(hasPhoto ? 0.5 : 0), location: 0),
                .init(color: .black.opacity(0), location: 0.25),
                .init(color: theme.paperColor.opacity(0), location: 0.45),
                .init(color: theme.paperColor, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: s.occasion.title, tint: theme.mutedInkColor)
                Text(s.recipientName)
                    .font(Typeface.display(40)).displayTracking(40)
                    .foregroundStyle(theme.inkColor)
                    .lineLimit(2).minimumScaleFactor(0.7)
                if let f = s.fromLine {
                    Text(f).font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func facts(_ s: Sendoff) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MetaLine(systemImage: s.state == .sealed ? "lock" : s.state == .open ? "envelope.open" : "clock", text: s.statusLine)
            if s.state != .open {
                MetaLine(systemImage: "person.2", text: countLine(s))
                MetaLine(systemImage: "lock", text: s.opensAt.map { "Opens \($0.formatted(.dateTime.weekday(.wide).month(.wide).day()))" } ?? "Opens when you say so")
            }
        }
        .padding(.top, 22)
    }

    @ViewBuilder
    private func actions(_ s: Sendoff) -> some View {
        HStack(spacing: 10) {
            switch s.state {
            case .collecting, .draft:
                PrimaryButton(title: "Share the link", systemImage: "square.and.arrow.up") { showShare = true }
                SecondaryButton(title: "Preview", systemImage: "eye", fill: false) { showPreview = true }
            case .sealed:
                PrimaryButton(title: "Preview the reveal", systemImage: "eye") { showPreview = true }
                SecondaryButton(title: "Share", systemImage: "square.and.arrow.up", fill: false) { showShare = true }
            case .open:
                PrimaryButton(title: "Read it again", systemImage: "book") { showPreview = true }
                // Opening it early ("Open it now") is when the recipient's link gets sent, so it
                // stays one tap away; the invite sheet is about gathering entries, which is over.
                ShareLink(item: s.revealURL) {
                    PillLabel(title: "Send link", systemImage: "square.and.arrow.up", fill: false)
                        .foregroundStyle(theme.inkColor)
                        .background(theme.controlColor, in: Capsule())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Send \(s.recipientFirstName) the link")
            }
        }
    }

    /// A Plus look nobody has paid for yet: what the recipient will see, and the way to keep it.
    private func lookLine(_ s: Sendoff) -> some View {
        let look = lookName(s.themeID)
        let instead = lookName(s.themeID.freeAlternative)
        let first = s.recipientFirstName
        return Button { showPaywall = true } label: {
            HStack(spacing: 6) {
                Text(s.state == .open
                     ? "\(first) sees \(instead). Add Plus or get \(look) and it changes to \(look)"
                     : "\(look) is a Plus look. Add Plus or get \(look) before it opens, or \(first) sees \(instead)")
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
            }
            .font(Typeface.caption)
            .foregroundStyle(theme.mutedInkColor)
        }
        .buttonStyle(.pressable)
    }

    private func lookName(_ id: ThemeID) -> String { ThemeCatalog.theme(id).name }

    /// Before it opens the organizer previews the look they chose, which is free to try. Once it
    /// is open, the preview shows what the recipient actually saw.
    private func previewSendoff(_ s: Sendoff) -> Sendoff {
        guard s.state == .open else { return s }
        var shown = s
        shown.themeID = purchases.look(for: s)
        return shown
    }

    /// The paywall, after entries arrive and never before. Free is a real option; this is an offer.
    private func keepLine(_ s: Sendoff) -> some View {
        let live = contributions.filter { $0.status != .hidden }.count
        let full = live >= s.contributorLimit
        return Button { showPaywall = true } label: {
            HStack(spacing: 6) {
                Text(full ? "Free holds \(s.contributorLimit), and it's full. Make room for everyone"
                          : "Free holds \(s.contributorLimit). Make it something they can keep")
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
            }
            .font(Typeface.caption)
            .foregroundStyle(full ? theme.inkColor : theme.mutedInkColor)
        }
        .buttonStyle(.pressable)
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Waiting for you · \(pending.count)").padding(.top, 36).padding(.bottom, 6)
            ForEach(pending) { c in
                VStack(alignment: .leading, spacing: 14) {
                    EntryPage(contribution: c, compact: true)
                    HStack(spacing: 10) {
                        SecondaryButton(title: "Hide", systemImage: "eye.slash", fill: false) { Task { await set(c, .hidden) } }
                        PrimaryButton(title: "Approve", systemImage: "checkmark", fill: false) { Task { await set(c, .approved) } }
                    }
                }
                .padding(.vertical, 18)
                if c.id != pending.last?.id { Rule() }
            }
        }
    }

    private func envelope(_ s: Sendoff) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "In the envelope · \(approved.count)").padding(.top, 36).padding(.bottom, 4)
            if approved.isEmpty {
                Text(s.isCollecting ? "Nothing yet. Share the link and the first ones arrive within the hour." : "No entries.")
                    .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                    .padding(.vertical, 14)
            }
            ForEach(approved) { c in
                EntryRow(contribution: c)
                    .contextMenu {
                        Button { Task { await pin(c) } } label: { Label(c.pinned ? "Unpin" : "Show first", systemImage: "pin") }
                        Button(role: .destructive) { Task { await set(c, .hidden) } } label: { Label("Hide", systemImage: "eye.slash") }
                    }
                if c.id != approved.last?.id { Rule() }
            }
        }
    }

    private var hiddenSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: "Hidden · \(hidden.count)").padding(.top, 36).padding(.bottom, 4)
            ForEach(hidden) { c in
                EntryRow(contribution: c)
                    .opacity(0.5)
                    .contextMenu {
                        Button { Task { await set(c, .approved) } } label: { Label("Put it back", systemImage: "arrow.uturn.left") }
                        Button(role: .destructive) { Task { try? await store.delete(contribution: c.id); await load() } } label: { Label("Delete", systemImage: "trash") }
                    }
                if c.id != hidden.last?.id { Rule() }
            }
        }
    }

    private func menu(_ s: Sendoff) -> some View {
        Menu {
            Button { showPreview = true } label: { Label("Preview the reveal", systemImage: "eye") }
            // The cover can change until it opens; after that it is what they saw.
            if s.state != .open {
                if let url = s.recipientPhotoURL {
                    Button { Task { await frame(url) } } label: { Label("Adjust cover photo", systemImage: "crop") }
                }
                Button { pickingPhoto = true } label: {
                    Label(s.recipientPhotoURL == nil ? "Add a cover photo" : "Change cover photo", systemImage: "photo")
                }
            }
            if approved.count > 1 {
                Button { showReorder = true } label: { Label("Reorder entries", systemImage: "arrow.up.arrow.down") }
            }
            if s.plan < .plus {
                Button { showPaywall = true } label: { Label("Make it something they can keep", systemImage: "seal") }
            }
            if s.state == .collecting {
                Button { Task { await setState(.sealed) } } label: { Label("Stop collecting and seal", systemImage: "lock") }
            }
            if s.state == .sealed || s.state == .collecting {
                Button { confirmOpen = true } label: { Label("Open it now", systemImage: "envelope.open") }
            }
            if s.state == .sealed {
                Button { Task { await setState(.collecting) } } label: { Label("Reopen for entries", systemImage: "lock.open") }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("More")
    }

    /// Reframes the photo already on the cover.
    private func frame(_ url: URL) async {
        let data: Data? = url.isFileURL ? try? Data(contentsOf: url) : try? await URLSession.shared.data(from: url).0
        guard let data, let image = CoverPhoto.image(from: data) else {
            coverError = "The photo didn't load. Check your connection and try again."
            return
        }
        framing = PhotoToFrame(image: image)
    }

    private func saveCover(_ image: UIImage, for id: UUID) async {
        do {
            guard let file = CoverPhoto.jpegFile(image) else { throw StoreError.notAllowed }
            try await store.setCover(file, for: id)
            await load()
        } catch {
            coverError = "That didn't save. Check your connection and try again."
        }
    }

    private func countLine(_ s: Sendoff) -> String {
        let n = approved.count + pending.count
        if let goal = s.contributorGoal { return "\(n) of \(goal) have added" }
        return n == 1 ? "1 person has added" : "\(n) people have added"
    }

    // MARK: Data

    private var pending: [Contribution] { contributions.filter { $0.status == .pending } }
    private var approved: [Contribution] { contributions.filter { $0.status == .approved } }
    private var hidden: [Contribution] { contributions.filter { $0.status == .hidden } }

    private func load() async {
        // Also tells the server about looks bought before it tracked them (see refreshOwnedThemes).
        async let looks: Void = purchases.refreshOwnedThemes()
        if let all = try? await store.mySendoffs(), let s = all.first(where: { $0.id == sendoffID }) { sendoff = s }
        await looks
        contributions = (try? await store.contributions(for: sendoffID)) ?? []
    }

    private func set(_ c: Contribution, _ status: ContributionStatus) async {
        try? await store.setStatus(c.id, status)
        await load()
    }

    private func pin(_ c: Contribution) async {
        var list = approved
        list.removeAll { $0.id == c.id }
        if !c.pinned { list.insert(c, at: 0) } else { list.append(c) }
        try? await store.reorder(sendoffID, orderedIDs: list.map(\.id))
        await load()
    }

    private func setState(_ state: SendoffState) async {
        try? await store.setState(sendoffID, state)
        await load()
    }
}

/// One entry in the organizer's list: who, and the first lines or what they attached.
struct EntryRow: View {
    @Environment(\.theme) private var theme
    var contribution: Contribution

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                (Text(contribution.authorName).font(Typeface.bodyStrong).foregroundColor(theme.inkColor)
                 + Text(contribution.authorRelationship.map { $0.isEmpty ? "" : " · \($0)" } ?? "")
                    .font(Typeface.body).foregroundColor(theme.faintInkColor))
                if let b = contribution.body, contribution.hasText {
                    Text(b).font(Typeface.caption).foregroundStyle(theme.mutedInkColor).lineLimit(2)
                }
                if !contribution.media.isEmpty {
                    Label(mediaLine, systemImage: mediaSymbol)
                        .labelStyle(TightLabel())
                        .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                }
            }
            Spacer(minLength: 0)
            if contribution.pinned {
                Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(theme.faintInkColor).padding(.top, 4)
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var mediaSymbol: String {
        if contribution.video != nil { return "video" }
        if contribution.voice != nil { return "waveform" }
        return "photo"
    }

    private var mediaLine: String {
        var parts: [String] = []
        let photos = contribution.photos.count
        if photos > 0 { parts.append(photos == 1 ? "1 photo" : "\(photos) photos") }
        if let v = contribution.voice { parts.append("Voice note · \(clock(v.durationSeconds))") }
        if let v = contribution.video { parts.append("Video · \(clock(v.durationSeconds))") }
        return parts.joined(separator: ", ")
    }

    private func clock(_ s: Double?) -> String {
        let n = Int(s ?? 0)
        return String(format: "%d:%02d", n / 60, n % 60)
    }
}

/// Drag entries into the order they are read in.
struct ReorderSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State var entries: [Contribution]
    var onSave: ([UUID]) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(entries) { c in
                    Text(c.signature).font(Typeface.body).foregroundStyle(theme.inkColor)
                        .listRowBackground(theme.raisedPaperColor)
                }
                .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(Paper())
            .navigationTitle("Reading order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onSave(entries.map(\.id)); dismiss() }
                }
            }
        }
        .tint(theme.inkColor)
    }
}

#Preview {
    let store = MockStore()
    return NavigationStack { SendoffDetailView(sendoffID: MockStore.sampleSendoff.id) }
        .appTheme()
        .environment(\.store, store)
        .environment(PurchaseManager(store: store))
}
