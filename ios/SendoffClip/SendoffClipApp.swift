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
            VStack(spacing: 16) {
                PathMark(size: 56)
                Text("Opening your Sendoff link").font(Typeface.title).foregroundStyle(theme.inkColor)
                ProgressView().tint(theme.mutedInkColor)
            }
        }
        .sendoffTheme(theme)
    }

    private func handoff(slug: String) -> some View {
        var url = AppConfig.publicOrigin.appending(path: "s/\(slug)/open")
        if let k = AppRouter.recipientKey(for: slug) { url.append(queryItems: [URLQueryItem(name: "k", value: k)]) }
        return ZStack {
            Paper()
            VStack(spacing: 18) {
                Seal(initial: "S", size: 72)
                Text("This one opens on the web.").font(Typeface.title).foregroundStyle(theme.inkColor)
                Text("The sealed envelope, the music and everything inside are waiting in Safari.")
                    .font(Typeface.ui).foregroundStyle(theme.mutedInkColor).multilineTextAlignment(.center)
                Link(destination: url) {
                    Text("Open it")
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(theme.onSealColor)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(theme.sealColor, in: RoundedRectangle(cornerRadius: theme.radius + 6))
                }
            }
            .padding(28)
        }
        .sendoffTheme(theme)
    }
}
