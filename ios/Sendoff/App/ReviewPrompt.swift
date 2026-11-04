import Foundation

/// When Sendoff asks for an App Store rating: after a Sendoff has done its job, never mid-task,
/// and once per Sendoff. The organizer is asked the first time they come back to one that has
/// been opened; a recipient who opened it in the app is asked on the last page. iOS decides
/// whether the prompt actually shows, and shows it at most three times a year. App Clips can't
/// ask, so this lives in the app only.
enum ReviewPrompt {
    private static let key = "ratingAskedFor"

    /// Asks after a pause, so the moment lands first. Does nothing if this Sendoff was asked about
    /// before, or if the screen goes away during the pause (it can ask next time instead).
    @MainActor
    static func ask(about id: UUID, after pause: Duration = .seconds(2), _ request: () -> Void) async {
        guard !wasAsked(about: id) else { return }
        do { try await Task.sleep(for: pause) } catch { return }
        markAsked(id)
        request()
    }

    static func wasAsked(about id: UUID) -> Bool {
        UserDefaults.standard.stringArray(forKey: key)?.contains(id.uuidString) ?? false
    }

    static func markAsked(_ id: UUID) {
        let asked = UserDefaults.standard.stringArray(forKey: key) ?? []
        UserDefaults.standard.set(asked + [id.uuidString], forKey: key)
    }
}
