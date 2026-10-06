import SwiftUI

/// The organizer tends a Sendoff: share, watch entries arrive, review, reorder, seal, open.
struct SendoffDetailView: View {
    @Environment(\.store) private var store
    @Environment(\.dismiss) private var dismiss
    var sendoffID: UUID

    @State private var sendoff: Sendoff?
    @State private var contributions: [Contribution] = []
    @State private var showShare = false
    @State private var showPreview = false
    @State private var editMode: EditMode = .inactive
    @State private var confirmOpen = false

    var body: some View {
        if let s = sendoff {
            let theme = ThemeCatalog.theme(s.themeID)
            ZStack {
                Paper()
                List {
                    Section {
                        cover(s)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    if s.moderation == .review, !pending.isEmpty {
                        Section {
                            ForEach(pending) { c in reviewRow(c, theme: theme) }
                        } header: {
                            sectionHeader("Waiting for you · \(pending.count)", theme)
                        }
                    }
                    Section {
                        if approved.isEmpty {
                            Text(s.isCollecting ? "Nothing yet. Share the link." : "No entries.")
                                .font(Typeface.ui).foregroundStyle(theme.mutedInkColor)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(approved) { c in
                            entryRow(c, theme: theme)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { Task { await set(c, .hidden) } } label: { Label("Hide", systemImage: "eye.slash") }
                                    Button { Task { await pin(c) } } label: { Label(c.pinned ? "Unpin" : "Pin first", systemImage: "pin") }.tint(theme.sealColor)
                                }
                        }
                        .onMove { from, to in
                            var list = approved
                            list.move(fromOffsets: from, toOffset: to)
                            Task { try? await store.reorder(s.id, orderedIDs: list.map(\.id)); await load() }
                        }
                    } header: {
                        HStack {
                            sectionHeader("In the envelope · \(approved.count)", theme)
                            Spacer()
                            if approved.count > 1 {
                                Button(editMode.isEditing ? "Done" : "Reorder") {
                                    withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                                }
                                .font(Typeface.caption).foregroundStyle(theme.sealColor)
                            }
                        }
                    }
                    if !hidden.isEmpty {
                        Section {
                            ForEach(hidden) { c in
                                entryRow(c, theme: theme).opacity(0.55)
                                    .swipeActions(edge: .trailing) {
                                        Button { Task { await set(c, .approved) } } label: { Label("Restore", systemImage: "arrow.uturn.left") }.tint(theme.sealColor)
                                        Button(role: .destructive) { Task { try? await store.delete(contribution: c.id); await load() } } label: { Label("Delete", systemImage: "trash") }
                                    }
                            }
                        } header: { sectionHeader("Hidden · \(hidden.count)", theme) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.editMode, $editMode)
            }
            .navigationTitle(s.recipientFirstName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button { showPreview = true } label: { Label("Preview the reveal", systemImage: "envelope.open") }
                        if s.state == .collecting {
                            Button { Task { await setState(.sealed) } } label: { Label("Stop collecting and seal", systemImage: "lock") }
                        }
                        if s.state == .sealed || s.state == .collecting {
                            Button { confirmOpen = true } label: { Label("Open it now", systemImage: "sparkles") }
                        }
                        if s.state == .sealed {
                            Button { Task { await setState(.collecting) } } label: { Label("Reopen for entries", systemImage: "lock.open") }
                        }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(theme.inkColor) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if s.isCollecting {
                    SealButton(title: "Share the link", systemImage: "square.and.arrow.up") { showShare = true }
                        .padding(20)
                        .background(theme.paperColor.opacity(0.96))
                }
            }
            .sheet(isPresented: $showShare) { ShareView(sendoff: s) }
            .fullScreenCover(isPresented: $showPreview) {
                RevealView(sendoff: s, contributions: approved, preview: true)
            }
            .confirmationDialog("Open it now?", isPresented: $confirmOpen, titleVisibility: .visible) {
                Button("Open for \(s.recipientFirstName)") { Task { await setState(.open) } }
            } message: {
                Text("\(s.recipientFirstName) will be able to break the seal right away. Entries stop here.")
            }
            .sendoffTheme(theme)
            .task { await load() }
            .refreshable { await load() }
        } else {
            ProgressView().task { await load() }
        }
    }

    // MARK: Pieces

    private func cover(_ s: Sendoff) -> some View {
        let theme = ThemeCatalog.theme(s.themeID)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Stamp(text: s.occasion.title)
                    Text(s.recipientName).font(Typeface.display(34)).foregroundStyle(theme.inkColor)
                    if let f = s.fromLine { Text(f).font(Typeface.signature).foregroundStyle(theme.mutedInkColor) }
                }
                Spacer()
                Seal(initial: s.recipientInitial, size: 64)
            }
            HStack(spacing: 18) {
                stat("\(approved.count)", "entries")
                stat("\(contributions.filter { !$0.media.isEmpty }.count)", "with media")
                stat(s.statusLine, nil)
            }
            if let goal = s.contributorGoal, s.isCollecting {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(theme.ruleColor)
                            Capsule().fill(theme.sealColor)
                                .frame(width: g.size.width * min(1, CGFloat(approved.count) / CGFloat(max(goal, 1))))
                        }
                    }
                    .frame(height: 4)
                    Text(approved.count >= goal ? "You hit your goal of \(goal). Share once more for the stragglers." : "\(approved.count) of \(goal). Share again if it stalls.")
                        .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                }
            }
            Rule()
        }
        .padding(20)
    }

    private func stat(_ value: String, _ label: String?) -> some View {
        let theme = ThemeCatalog.theme(sendoff?.themeID ?? .letterpress)
        return VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: label == nil ? 15 : 22, weight: .semibold, design: .serif)).foregroundStyle(theme.inkColor)
            if let label { Text(label).font(Typeface.caption).foregroundStyle(theme.mutedInkColor) }
        }
    }

    private func sectionHeader(_ text: String, _ theme: SendoffTheme) -> some View {
        Text(text.uppercased()).font(Typeface.stamp).kerning(1.1).foregroundStyle(theme.mutedInkColor)
    }

    private func entryRow(_ c: Contribution, theme: SendoffTheme) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if c.pinned { Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(theme.sealColor).padding(.top, 4) }
            VStack(alignment: .leading, spacing: 4) {
                Text(c.signature).font(Typeface.uiStrong).foregroundStyle(theme.inkColor)
                if let b = c.body, c.hasText {
                    Text(b).font(Typeface.caption).foregroundStyle(theme.mutedInkColor).lineLimit(2)
                }
                if !c.media.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(c.media) { m in
                            Image(systemName: m.kind == .photo ? "photo" : m.kind == .voice ? "waveform" : "video")
                                .font(.system(size: 11))
                        }
                    }
                    .foregroundStyle(theme.sealColor)
                }
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .listRowBackground(Color.clear)
    }

    private func reviewRow(_ c: Contribution, theme: SendoffTheme) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            EntryPage(contribution: c)
            HStack(spacing: 10) {
                QuietButton(title: "Hide", systemImage: "eye.slash") { Task { await set(c, .hidden) } }
                SealButton(title: "Approve", systemImage: "checkmark") { Task { await set(c, .approved) } }
            }
        }
        .padding(.vertical, 8)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: Data

    private var pending: [Contribution] { contributions.filter { $0.status == .pending } }
    private var approved: [Contribution] { contributions.filter { $0.status == .approved } }
    private var hidden: [Contribution] { contributions.filter { $0.status == .hidden } }

    private func load() async {
        if let all = try? await store.mySendoffs(), let s = all.first(where: { $0.id == sendoffID }) { sendoff = s }
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

#Preview {
    NavigationStack { SendoffDetailView(sendoffID: MockStore.sampleSendoff.id) }
        .environment(\.store, MockStore())
}
