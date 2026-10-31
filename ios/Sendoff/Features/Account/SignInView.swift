import SwiftUI
import AuthenticationServices
import CryptoKit

/// Organizers sign in with Apple before their first Sendoff, so it follows them to a new phone.
/// Nobody who adds to a Sendoff, and nobody who opens one, ever needs an account.
struct SignInView: View {
    @Environment(\.store) private var store
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    /// Called after a successful sign-in, once the sheet has been dismissed.
    var onSignedIn: () -> Void

    @State private var nonce = ""
    @State private var askName = false
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        ZStack {
            Paper()
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    CircleButton(systemImage: "xmark", label: "Close") { dismiss() }
                    Spacer()
                }
                Spacer()
                PathMark(size: 40, onTile: false)
                Eyebrow(text: askName ? "One more thing" : "Start a Sendoff").padding(.top, 28)
                Text(askName ? "What should people\ncall you?" : "Sign in to keep\ntrack of it.")
                    .font(Typeface.display(40)).displayTracking(40)
                    .foregroundStyle(theme.inkColor)
                    .padding(.top, 10)
                Text(askName
                     ? "Everyone who adds to your Sendoff sees it: \u{201C}Only Jo and you will see this.\u{201D}"
                     : "Your Sendoffs stay with your Apple Account, so they move with you to a new phone. Only you need an account. Everyone who adds, and the person it\u{2019}s for, just uses a link.")
                    .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                Spacer()
                if askName {
                    Field(label: "Your name", text: $name, placeholder: "Dan Okafor").textContentType(.name)
                    PrimaryButton(title: busy ? "Saving…" : "Continue") { Task { await saveName() } }
                        .disabled(busy || name.trimmingCharacters(in: .whitespaces).count < 2)
                        .padding(.top, 16)
                } else {
                    SignInWithAppleButton(.signIn) { request in
                        nonce = Self.randomNonce()
                        request.requestedScopes = [.fullName, .email]
                        request.nonce = Self.sha256(nonce)
                    } onCompletion: { result in
                        Task { await finish(result) }
                    }
                    .signInWithAppleButtonStyle(scheme == .dark ? .white : .black)
                    .frame(height: 50)
                    .clipShape(Capsule())
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)
                }
                if let error {
                    Text(error).font(Typeface.caption).foregroundStyle(theme.inkColor).padding(.top, 12)
                }
            }
            .padding(20)
        }
        .tint(theme.inkColor)
        .interactiveDismissDisabled(askName)
    }

    private func finish(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let e):
            if (e as? ASAuthorizationError)?.code != .canceled { error = "Apple didn\u{2019}t sign you in. Try again." }
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken, let token = String(data: tokenData, encoding: .utf8)
            else { error = "Apple didn\u{2019}t send what we need. Try again."; return }
            let given = credential.fullName.map { PersonNameComponentsFormatter().string(from: $0) } ?? ""
            busy = true
            defer { busy = false }
            do {
                if try await store.signInWithApple(idToken: token, nonce: nonce, name: given) {
                    done()
                } else {
                    name = given
                    withAnimation(Motion.settle) { askName = true }
                }
            } catch {
                self.error = "That didn\u{2019}t go through. Check your connection and try again."
            }
        }
    }

    private func saveName() async {
        busy = true
        defer { busy = false }
        do {
            try await store.setDisplayName(name)
            done()
        } catch {
            self.error = "That didn\u{2019}t save. Try again."
        }
    }

    private func done() {
        dismiss()
        onSignedIn()
    }

    // MARK: Nonce (Apple gets the hash; Supabase checks it against the raw value)

    private static func randomNonce(length: Int = 32) -> String {
        let chars = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in chars[Int(generator.next() % UInt64(chars.count))] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

#Preview {
    SignInView {}.appTheme().environment(\.store, MockStore())
}
