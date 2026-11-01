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
                    VStack(alignment: .leading, spacing: 0) {
                        Eyebrow(text: "Invite people")
                        Text("Share the link.\nGather the words.")
                            .font(Typeface.display(40)).displayTracking(40)
                            .foregroundStyle(theme.inkColor)
                            .padding(.top, 10)

                        card.padding(.top, 28)

                        Text("\(sendoff.recipientFirstName) gets a different link on the day. It stays sealed until then.")
                            .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                            .padding(.top, 16)
                        ShareLink(item: sendoff.revealURL) {
                            PillLabel(title: "Share \(sendoff.recipientFirstName)'s own link", systemImage: "envelope", fill: false, small: true)
                                .foregroundStyle(theme.inkColor)
                                .background(theme.controlColor, in: Capsule())
                        }
                        .buttonStyle(.pressable)
                        .padding(.top, 12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 40)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close")
                }
            }
        }
        .tint(theme.inkColor)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CoverImage(sendoff: sendoff)
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("For \(sendoff.recipientFirstName), from everyone").font(Typeface.name).foregroundStyle(theme.inkColor)
                    Button {
                        UIPasteboard.general.string = sendoff.shareURL.absoluteString
                        withAnimation(Motion.tap) { copied = true }
                        Task { try? await Task.sleep(for: .seconds(1.6)); withAnimation { copied = false } }
                    } label: {
                        Text(copied ? "Copied" : sendoff.shareURL.absoluteString.replacingOccurrences(of: "https://", with: ""))
                            .font(Typeface.caption).foregroundStyle(theme.faintInkColor)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    .accessibilityHint("Copies the link")
                }
            }

            if let img = QR.image(for: sendoff.shareURL.absoluteString, ink: "#0E0E0D", paper: "#F3F1EC") {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 168, height: 168)
                    .padding(16)
                    .background(Color(red: 0.953, green: 0.945, blue: 0.925), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 22)
                    .accessibilityLabel("QR code for the link")
            }

            Text("Anyone with the link can add a note, a photo, a voice memo or a short video. Only \(sendoff.recipientFirstName) and you will read them.")
                .font(Typeface.body).foregroundStyle(theme.mutedInkColor)
                .padding(.top, 20)

            HStack(spacing: 10) {
                ShareLink(item: message) {
                    PillLabel(title: "Share link", systemImage: "square.and.arrow.up")
                        .foregroundStyle(theme.onSealColor)
                        .background(theme.sealColor, in: Capsule())
                }
                .buttonStyle(.pressable)
                if let img = QR.image(for: sendoff.shareURL.absoluteString, ink: "#0E0E0D", paper: "#FFFFFF", scale: 12) {
                    ShareLink(item: Image(uiImage: img), preview: SharePreview("Sendoff for \(sendoff.recipientName)", image: Image(uiImage: img))) {
                        PillLabel(title: "Save QR", systemImage: "arrow.down.to.line")
                            .foregroundStyle(theme.inkColor)
                            .background(theme.controlColor, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.top, 18)
        }
        .padding(20)
        .background(theme.raisedPaperColor, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
    ShareView(sendoff: MockStore.sampleCollecting).appTheme()
}
