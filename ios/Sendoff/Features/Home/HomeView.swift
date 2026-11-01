import SwiftUI

/// The organizer's library: what is in progress as photo cards, what has opened as a list.
struct HomeView: View {
    @Environment(\.store) private var store
    @Environment(\.theme) private var theme
    @State private var sendoffs: [Sendoff] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var showSignIn = false
    @State private var createAfterSignIn = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Paper()
                GeometryReader { g in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                        if loading {
                            ProgressView().tint(theme.faintInkColor).frame(maxWidth: .infinity).padding(.top, 80)
                        } else if sendoffs.isEmpty {
                            empty
                        } else {
                            if !inProgress.isEmpty {
                                Eyebrow(text: "In progress").padding(.horizontal, 20).padding(.top, 30)
                                carousel(height: min(g.size.height * 0.48, 420))
                            }
                            if !opened.isEmpty {
                                Eyebrow(text: "Opened").padding(.horizontal, 20).padding(.top, 32)
                                VStack(spacing: 0) {
                                    ForEach(opened) { s in
                                        NavigationLink(value: s) { OpenedRow(sendoff: s) }
                                            .buttonStyle(.pressable)
                                        if s.id != opened.last?.id { Rule() }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.top, 4)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
                }
            }
            .navigationDestination(for: Sendoff.self) { s in
                SendoffDetailView(sendoffID: s.id)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSignIn, onDismiss: {
                if createAfterSignIn, store.isSignedIn { showCreate = true }
                createAfterSignIn = false
                Task { await load() }
            }) {
                SignInView {}.appTheme()
            }
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                CreateFlow { created in
                    showCreate = false
                    path.append(created)
                }
            }
            .task { await load() }
        }
        .tint(theme.inkColor)
    }

    /// Creating needs an organizer account; signing in comes first, then the create flow opens.
    private func start() {
        if store.isSignedIn { showCreate = true } else { createAfterSignIn = true; showSignIn = true }
    }

    private var inProgress: [Sendoff] { sendoffs.filter { $0.state != .open } }
    private var opened: [Sendoff] { sendoffs.filter { $0.state == .open } }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                PathMark(size: 26, onTile: false)
                Spacer()
                if store.isSignedIn { account }
                CircleButton(systemImage: "plus", label: "Start a Sendoff") { start() }
            }
            .frame(height: 52)
            Text("Sendoffs")
                .font(Typeface.display(40)).displayTracking(40)
                .foregroundStyle(theme.inkColor)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private func carousel(height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(inProgress) { s in
                    NavigationLink(value: s) { SendoffCard(sendoff: s, height: height) }
                        .buttonStyle(.pressable)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, 20)
        }
        .scrollTargetBehavior(.viewAligned)
        .padding(.top, 12)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Everyone adds privately.\nOne person opens it, on the day.")
                .font(Typeface.title).displayTracking(28)
                .foregroundStyle(theme.inkColor)
            Text("The card passed around the office gets lost, and half the team never sees it. A Sendoff is sealed until the day, and only they read it.")
                .font(Typeface.body)
                .foregroundStyle(theme.mutedInkColor)
            PrimaryButton(title: "Start a Sendoff", systemImage: "plus", fill: false) { start() }
                .padding(.top, 8)
            if !store.isSignedIn {
                Button("Already started one? Sign in") { showSignIn = true }
                    .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 36)
    }

    private var account: some View {
        Menu {
            Section(store.currentUserName.isEmpty ? "Signed in" : "Signed in as \(store.currentUserName)") {
                Button(role: .destructive) {
                    Task { try? await store.signOut(); sendoffs = []; await load() }
                } label: { Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right") }
            }
        } label: {
            Image(systemName: "person")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.inkColor)
                .frame(width: 44, height: 44)
                .background(theme.controlColor, in: Circle())
        }
        .accessibilityLabel("Account")
    }

    private func load() async {
        loading = sendoffs.isEmpty
        sendoffs = (try? await store.mySendoffs()) ?? []
        loading = false
    }
}

/// A Sendoff in progress: the recipient's photo with their name set on it.
struct SendoffCard: View {
    var sendoff: Sendoff
    var height: CGFloat = 390

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CoverImage(sendoff: sendoff)
                .frame(width: 268, height: height)
                .clipped()
            if sendoff.recipientPhotoURL != nil { Scrim() }
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: stateWord, tint: onPhoto.opacity(0.82))
                Text(sendoff.recipientName)
                    .font(Typeface.title).displayTracking(28)
                    .foregroundStyle(onPhoto)
                    .lineLimit(2)
                HStack(spacing: 14) {
                    ForEach(details, id: \.1) { icon, text in
                        Label(text, systemImage: icon).labelStyle(TightLabel())
                    }
                }
                .font(Typeface.caption)
                .foregroundStyle(onPhoto.opacity(0.88))
            }
            .padding(18)
        }
        .frame(width: 268, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @Environment(\.theme) private var theme
    private var onPhoto: Color { sendoff.recipientPhotoURL != nil ? .white : theme.inkColor }

    private var stateWord: String {
        switch sendoff.state {
        case .draft: "Draft"
        case .collecting: "Collecting"
        case .sealed: "Sealed"
        case .open: "Open"
        }
    }

    private var details: [(String, String)] {
        switch sendoff.state {
        case .collecting:
            var d: [(String, String)] = []
            if let c = sendoff.closesAt { d.append(("clock", "Closes \(c.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")) }
            return d
        case .sealed:
            if let o = sendoff.opensAt { return [("lock", "Opens \(o.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")] }
            return [("lock", "Opens when you say so")]
        default: return []
        }
    }
}

/// A Sendoff that has opened: a thumbnail and a line.
struct OpenedRow: View {
    @Environment(\.theme) private var theme
    var sendoff: Sendoff

    var body: some View {
        HStack(spacing: 14) {
            CoverImage(sendoff: sendoff)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(sendoff.recipientName).font(Typeface.name).foregroundStyle(theme.inkColor)
                Text(line).font(Typeface.caption).foregroundStyle(theme.faintInkColor)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.faintInkColor)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var line: String {
        var parts = [sendoff.occasion.title]
        if let o = sendoff.openedAt ?? sendoff.opensAt { parts.append("opened \(o.formatted(.dateTime.month(.abbreviated).day()))") }
        return parts.joined(separator: " · ")
    }
}

/// Icon and title with a tight gap, for metadata on cards.
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.imageScale(.small); configuration.title }
    }
}

#Preview {
    let store = MockStore()
    return HomeView().appTheme().environment(\.store, store).environment(AppRouter()).environment(PurchaseManager(store: store))
}
