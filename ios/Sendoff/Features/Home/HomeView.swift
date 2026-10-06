import SwiftUI

/// The organizer's library. Quiet. The reveal is where color is spent.
struct HomeView: View {
    @Environment(\.store) private var store
    @State private var sendoffs: [Sendoff] = []
    @State private var loading = true
    @State private var showCreate = false
    @State private var path = NavigationPath()

    private let theme = ThemeCatalog.theme(.letterpress)

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Paper()
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        header
                        if loading {
                            ProgressView().tint(theme.mutedInkColor).frame(maxWidth: .infinity).padding(.top, 60)
                        } else if sendoffs.isEmpty {
                            empty
                        } else {
                            VStack(spacing: 14) {
                                ForEach(sendoffs) { s in
                                    NavigationLink(value: s) { SendoffRow(sendoff: s) }
                                        .buttonStyle(.pressable)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
                VStack {
                    Spacer()
                    SealButton(title: "Start a Sendoff", systemImage: "plus") { showCreate = true }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                        .background(
                            LinearGradient(colors: [theme.paperColor.opacity(0), theme.paperColor], startPoint: .top, endPoint: .bottom)
                                .frame(height: 140).offset(y: -20), alignment: .bottom
                        )
                }
            }
            .navigationDestination(for: Sendoff.self) { s in
                SendoffDetailView(sendoffID: s.id)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
                CreateFlow { created in
                    showCreate = false
                    path.append(created)
                }
            }
            .task { await load() }
        }
        .sendoffTheme(theme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                PathMark(size: 34)
                Text("Sendoff")
                    .font(Typeface.title)
                    .foregroundStyle(theme.inkColor)
                Spacer()
                Seal(initial: String(store.currentUserName.prefix(1)), size: 36)
            }
            Text(sendoffs.isEmpty ? "Nothing in the post yet." : "\(sendoffs.count) in the post")
                .font(Typeface.ui)
                .foregroundStyle(theme.mutedInkColor)
        }
        .padding(.top, 24)
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rule()
            Text("The card that gets passed around the office gets lost. Half the team never sees it. The other half writes \u{201C}good luck\u{201D} because everyone will read it.")
                .font(Typeface.entry)
                .foregroundStyle(theme.inkColor)
                .lineSpacing(5)
            Text("A Sendoff is a sealed envelope. Everyone adds privately. One person opens it, once, on the day.")
                .font(Typeface.entry)
                .foregroundStyle(theme.mutedInkColor)
                .lineSpacing(5)
            Rule()
        }
        .padding(.top, 20)
    }

    private func load() async {
        loading = sendoffs.isEmpty
        sendoffs = (try? await store.mySendoffs()) ?? []
        loading = false
    }
}

/// A row in the library, drawn in the Sendoff's own theme so the list reads as a shelf.
struct SendoffRow: View {
    var sendoff: Sendoff

    var body: some View {
        let t = ThemeCatalog.theme(sendoff.themeID)
        HStack(spacing: 16) {
            Seal(initial: sendoff.recipientInitial, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                Text(sendoff.recipientName)
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(t.inkColor)
                HStack(spacing: 8) {
                    Stamp(text: sendoff.occasion.title, tint: t.mutedInkColor)
                    Text(sendoff.statusLine)
                        .font(Typeface.caption)
                        .foregroundStyle(t.mutedInkColor)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(t.mutedInkColor)
        }
        .padding(16)
        .background(t.paperColor, in: RoundedRectangle(cornerRadius: t.radius + 6))
        .overlay(RoundedRectangle(cornerRadius: t.radius + 6).stroke(t.isDark ? Color.clear : t.ruleColor))
        .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
        .environment(\.theme, t)
    }
}

#Preview {
    HomeView().environment(\.store, MockStore()).environment(AppRouter())
}
