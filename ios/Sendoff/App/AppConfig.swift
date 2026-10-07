import Foundation

/// Build-time configuration. Values come from `Config/Local.xcconfig` through Info.plist, so the
/// public domain, Supabase project and team id are never hardcoded in source.
enum AppConfig {
    /// Host the web pages are served from, for example `sendoffapp.com`. Also the associated domain
    /// for universal links and the App Clip (`PUBLIC_HOST` in the xcconfig).
    static var publicHost: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "PublicHost") as? String
        return (v?.isEmpty == false ? v : nil) ?? "sendoffapp.com"
    }

    static var publicOrigin: URL { URL(string: "https://\(publicHost)")! }

    /// Where stock music is served from (Supabase public bucket or a CDN). `MUSIC_BASE_URL` in the xcconfig.
    static var musicBaseURL: URL? {
        guard let s = Bundle.main.object(forInfoDictionaryKey: "MusicBaseURL") as? String, !s.isEmpty else { return nil }
        return URL(string: s)
    }
}
