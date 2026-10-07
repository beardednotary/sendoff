import SwiftUI
import Observation

// Shared by the app and the App Clip. `SendoffApp.swift` (app) and `SendoffClipApp.swift` (clip)
// each build on this.

// MARK: - Store in the environment

private struct StoreKey: EnvironmentKey {
    static let defaultValue: any SendoffStore = MockStore()
}

extension EnvironmentValues {
    var store: any SendoffStore {
        get { self[StoreKey.self] }
        set { self[StoreKey.self] = newValue }
    }
}

// MARK: - Router

/// Handles `https://{PUBLIC_HOST}/s/{slug}?t={token}` (contribute),
/// `https://{PUBLIC_HOST}/s/{slug}/open?k={key}` (reveal) and `sendoff://` equivalents.
@Observable
final class AppRouter {
    enum Destination: Hashable {
        case contribute(slug: String)
        case reveal(slug: String)
    }

    var pending: Destination?

    private static var tokens: [String: String] = [:]
    private static var keys: [String: String] = [:]

    static func pendingToken(for slug: String) -> String? { tokens[slug] }
    static func recipientKey(for slug: String) -> String? { keys[slug] }

    func handle(url: URL) {
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let sIndex = parts.firstIndex(of: "s"), parts.count > sIndex + 1 else { return }
        let slug = parts[sIndex + 1]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if parts.count > sIndex + 2, parts[sIndex + 2] == "open" {
            if let k = query.first(where: { $0.name == "k" })?.value { Self.keys[slug] = k }
            pending = .reveal(slug: slug)
        } else {
            if let t = query.first(where: { $0.name == "t" })?.value { Self.tokens[slug] = t }
            pending = .contribute(slug: slug)
        }
    }
}

extension AppRouter.Destination: Identifiable {
    var id: String {
        switch self {
        case .contribute(let s): "c-\(s)"
        case .reveal(let s): "r-\(s)"
        }
    }
}
