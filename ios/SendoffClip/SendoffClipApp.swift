import SwiftUI

/// The App Clip: someone taps the shared link or scans the QR code on an iPhone without the
/// app, and gets the native contribute flow with no install. Nothing else; the reveal and the
/// organizer's tools live in the full app and on the web.
///
/// Shares Models, Design, Services and Features/Contribute with the app (see ios/project.yml).
@main
struct SendoffClipApp: App {
    @State private var router = AppRouter()
    @State private var store: any SendoffStore = SupabaseStore.fromInfoPlist() ?? MockStore()

    var body: some Scene {
        WindowGroup {
            ClipRootView()
                .environment(router)
                .environment(\.store, store)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { router.handle(url: url) }
                }
                .onOpenURL { router.handle(url: $0) }
        }
    }
}

struct ClipRootView: View {
    @Environment(AppRouter.self) private var router
    private let theme = ThemeCatalog.theme(.letterpress)

    var body: some View {
        switch router.pending {
        case .contribute(let slug):
            ContributeFlow(slug: slug)
        case .reveal(let slug):
            // The clip does not carry the reveal; hand the recipient to the web page.
            handoff(slug: slug)
        case nil:
            waiting
        }
    }

    private var waiting: some View {
        ZStack {
            Paper()
            VStack(spacing: 18) {
                PathMark(size: 56)
                Text("Opening your Sendoff link").font(Typeface.title).foregroundStyle(theme.inkColor)
                ProgressView().tint(theme.faintInkColor)
            }
        }
        .sendoffTheme(theme)
    }

    private func handoff(slug: String) -> some View {
        var url = AppConfig.publicOrigin.appending(path: "s/\(slug)/open")
        if let k = AppRouter.recipientKey(for: slug) { url.append(queryItems: [URLQueryItem(name: "k", value: k)]) }
        return ZStack {
            Paper()
            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                PathMark(size: 56)
                Text("This one opens\non the web.")
                    .font(Typeface.display(40)).displayTracking(40)
                    .foregroundStyle(theme.inkColor)
                    .padding(.top, 28)
                Text("The seal, the music and everything inside are waiting in Safari.")
                    .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                    .padding(.top, 12)
                Spacer()
                Link(destination: url) {
                    PillLabel(title: "Open it")
                        .foregroundStyle(theme.onSealColor)
                        .background(theme.sealColor, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
            .padding(20)
        }
        .sendoffTheme(theme)
    }
}
