import SwiftUI
import CoreImage.CIFilterBuiltins

/// The share screen. One link, a QR code for the break room, a pre-written message.
struct ShareView: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    var sendoff: Sendoff
    @State private var copied = false

    private var message: String {
        """
        We're putting together a Sendoff for \(sendoff.recipientName). Add a note, a photo, a voice memo or a short video. Only \(sendoff.recipientFirstName) and I will see what you add.

        \(sendoff.shareURL.absoluteString)
        \(sendoff.closesAt.map { "Please add yours by \($0.formatted(.dateTime.weekday(.wide).month().day()))." } ?? "")
        """
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Paper()
                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 8) {
                            Stamp(text: "Share with everyone")
                            Text("One link. Anyone, any device.")
                                .font(Typeface.title).foregroundStyle(theme.inkColor)
                                .multilineTextAlignment(.center)
                            Text("Contributors don't need the app or an account. Each person only ever sees their own entry.")
                                .font(Typeface.ui).foregroundStyle(theme.mutedInkColor)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)

                        if let img = QR.image(for: sendoff.shareURL.absoluteString, ink: theme.ink, paper: theme.paper) {
                            Image(uiImage: img)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 200, height: 200)
                                .padding(16)
                                .background(theme.paperColor, in: RoundedRectangle(cornerRadius: theme.radius))
                                .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.ruleColor))
                                .overlay(Seal(initial: sendoff.recipientInitial, size: 44))
                        }

                        VStack(spacing: 10) {
                            Button {
                                UIPasteboard.general.string = sendoff.shareURL.absoluteString
                                withAnimation(Motion.tap) { copied = true }
                                Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { copied = false } }
                            } label: {
                                HStack {
                                    Text(sendoff.shareURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundStyle(theme.inkColor)
                                    Spacer()
                                    Text(copied ? "Copied" : "Copy").font(Typeface.caption).foregroundStyle(theme.sealColor)
                                }
                                .padding(14)
                                .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: theme.radius))
                                .overlay(RoundedRectangle(cornerRadius: theme.radius).stroke(theme.ruleColor))
                            }
                            .buttonStyle(.pressable)

                            ShareLink(item: message) {
                                HStack(spacing: 8) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Send the link")
                                }
                                .font(.system(size: 18, weight: .semibold, design: .serif))
                                .foregroundStyle(theme.onSealColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(theme.sealColor, in: RoundedRectangle(cornerRadius: theme.radius + 6))
                            }
                            .buttonStyle(.pressable)

                            if let img = QR.image(for: sendoff.shareURL.absoluteString, ink: theme.ink, paper: theme.paper, scale: 12) {
                                ShareLink(item: Image(uiImage: img), preview: SharePreview("Sendoff for \(sendoff.recipientName)", image: Image(uiImage: img))) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "qrcode")
                                        Text("Save the QR code for a poster")
                                    }
                                    .font(Typeface.uiStrong)
                                    .foregroundStyle(theme.inkColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .overlay(RoundedRectangle(cornerRadius: theme.radius + 6).stroke(theme.inkColor.opacity(0.35)))
                                }
                                .buttonStyle(.pressable)
                            }
                        }

                        Rule()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recipient's link").font(Typeface.uiStrong).foregroundStyle(theme.inkColor)
                            Text("Different from the one above. Give it to \(sendoff.recipientFirstName) on the day, or print its QR code inside a card. It stays sealed until the reveal.")
                                .font(Typeface.caption).foregroundStyle(theme.mutedInkColor)
                            ShareLink(item: sendoff.revealURL) {
                                Label("Share \(sendoff.recipientFirstName)'s link", systemImage: "envelope")
                                    .font(Typeface.uiStrong).foregroundStyle(theme.sealColor)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(20)
                }
            }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.foregroundStyle(theme.inkColor) } }
        }
    }
}

enum QR {
    static func image(for string: String, ink: HexColor, paper: HexColor, scale: CGFloat = 8) -> UIImage? {
        let ctx = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let colored = CIFilter.falseColor()
        colored.inputImage = output
        let i = ink.rgb, p = paper.rgb
        colored.color0 = CIColor(red: i.r, green: i.g, blue: i.b)
        colored.color1 = CIColor(red: p.r, green: p.g, blue: p.b)
        guard let out = colored.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)),
              let cg = ctx.createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

#Preview {
    ShareView(sendoff: MockStore.sampleCollecting).sendoffTheme(ThemeCatalog.theme(.letterpress))
}
