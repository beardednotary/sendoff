import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Sendoff

/// The App Store screenshots: the app's own screens with the demo data, each under one line of
/// serif on Evening black. Written at the two iPhone sizes App Store Connect takes, 6.3" (1206 x
/// 2622, the one the version page asks for) and 6.9" (1320 x 2868), into a folder for each. Run on
/// an iPhone Pro Max simulator. Skipped unless a folder is given:
///   TEST_RUNNER_STORE_SCREENS_DIR=/path xcodebuild test ... -only-testing:SendoffTests/StoreScreens
/// The rest of the listing is in docs/APP_STORE.md.
@MainActor
final class StoreScreens: XCTestCase {
    private struct Shot {
        var name: String
        var eyebrow: String
        var headline: String
        /// The ink of the drawn status bar; nil where the screen hides it (the reveal).
        var statusBar: Color?
        /// The app's own screens follow the system appearance; they're shown in dark, like the page.
        var dark = false
        var screen: AnyView
    }

    func testStoreScreens() async throws {
        guard let dir = ProcessInfo.processInfo.environment["STORE_SCREENS_DIR"] else { throw XCTSkip("STORE_SCREENS_DIR not set") }
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first)
        XCTAssertEqual(window.bounds.size, CGSize(width: 440, height: 956), "Run on a 6.9-inch iPhone so the screens are 1320 x 2868")

        let store = MockStore()
        let purchases = PurchaseManager(store: store)
        let maria = MockStore.sampleSendoff, jo = MockStore.sampleCollecting
        let entries = MockStore.sampleContributions(for: maria.id)
        // The Kept shot is the recipient's last page, where the app would ask for a rating.
        ReviewPrompt.markAsked(maria.id)
        let paperInk = ThemeCatalog.theme(.letterpress).inkColor
        let eveningInk = ThemeCatalog.theme(.midnightToast).inkColor
        var note = ContributionDraft()
        note.promptUsed = "What the next team is lucky to get"
        note.body = "Someone who reads the whole doc before the meeting, then asks the question everyone else was afraid to. They have no idea how lucky they are."
        note.authorName = "Marcus Bell"
        note.authorRelationship = "Two desks down, since 2021"

        // In the order they go on the product page; search results show the first three.
        let shots = [
            Shot(name: "1-sealed", eyebrow: "Sendoff", headline: "Everyone’s words,\nsealed until the day.", statusBar: nil,
                 screen: AnyView(RevealView(sendoff: maria, contributions: entries, at: .sealed))),
            Shot(name: "2-cover", eyebrow: "On the day", headline: "Their photo, their name,\nthen everyone’s words.", statusBar: nil,
                 screen: AnyView(RevealView(sendoff: maria, contributions: entries, at: .cover))),
            Shot(name: "3-contribute", eyebrow: "Everyone adds", headline: "A note, photos,\na voice, a video.", statusBar: paperInk,
                 screen: AnyView(ContributeFlow(slug: jo.slug, draft: note))),
            Shot(name: "4-entry", eyebrow: "On the day", headline: "Opened one at a time,\nlike letters.", statusBar: nil,
                 screen: AnyView(RevealView(sendoff: maria, contributions: entries, at: .entry(0)))),
            Shot(name: "5-voice", eyebrow: "Voice notes", headline: "The part they’ll\nplay again.", statusBar: nil,
                 screen: AnyView(RevealView(sendoff: maria, contributions: entries, at: .entry(2)))),
            Shot(name: "6-photos", eyebrow: "Photos and video", headline: "Everyone who was there,\nin one place.", statusBar: nil,
                 screen: AnyView(RevealView(sendoff: maria, contributions: entries, at: .entry(3)))),
            Shot(name: "7-share", eyebrow: "One link", headline: "No app to install,\nno account to make.", statusBar: eveningInk, dark: true,
                 screen: AnyView(ShareView(sendoff: jo).appTheme())),
            Shot(name: "8-organizer", eyebrow: "For the organizer", headline: "See each one arrive,\nand set the order.", statusBar: eveningInk, dark: true,
                 screen: AnyView(NavigationStack { SendoffDetailView(sendoffID: maria.id) }.appTheme())),
            Shot(name: "9-kept", eyebrow: "Theirs to keep", headline: "Come back to it,\nor save it as a PDF.", statusBar: nil,
                 screen: AnyView(RevealView(sendoff: maria, contributions: entries, at: .kept))),
        ]

        for shot in shots {
            // The reveal and the contribute page set their own appearance from the Sendoff's look.
            window.overrideUserInterfaceStyle = shot.dark ? .dark : .unspecified
            let root = shot.dark ? AnyView(shot.screen.environment(\.colorScheme, .dark)) : shot.screen
            window.rootViewController = UIHostingController(rootView: root
                .environment(\.store, store)
                .environment(purchases)
                .environment(AppRouter()))
            window.makeKeyAndVisible()
            // The demo photos come from Unsplash.
            try await Task.sleep(for: .seconds(5))
            let screen = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let framed = StoreFrame(screen: screen, eyebrow: shot.eyebrow, headline: shot.headline,
                                    statusBar: shot.statusBar, canvas: window.bounds.size)
            for (folder, pixels) in Self.sizes {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(folder)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                try XCTUnwrap(Self.flatPNG(framed, canvas: window.bounds.size, pixels: pixels))
                    .write(to: url.appendingPathComponent("\(shot.name).png"))
            }
        }
    }

    /// The 6.3" canvas is a hair narrower than the 6.9" one, so that size is the same picture
    /// scaled to its height, with under a pixel of background trimmed from each side.
    private static let sizes: [(String, CGSize)] = [("6.3-inch", CGSize(width: 1206, height: 2622)),
                                                    ("6.9-inch", CGSize(width: 1320, height: 2868))]

    /// App Store Connect wants RGB with no alpha channel, which UIImage's PNGs always carry, so
    /// the render is drawn into an sRGB bitmap without one and written with ImageIO.
    private static func flatPNG(_ view: some View, canvas: CGSize, pixels: CGSize) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = max(pixels.width / canvas.width, pixels.height / canvas.height)
        renderer.isOpaque = true
        guard let image = renderer.cgImage, let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        context.draw(image, in: CGRect(x: (pixels.width - w) / 2, y: (pixels.height - h) / 2, width: w, height: h))
        let data = NSMutableData()
        guard let flat = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, flat, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}

/// One screenshot: a tracked eyebrow, a serif headline, and the screen in a plain iPhone outline
/// that runs off the bottom edge. Laid out in points on the device's own canvas.
private struct StoreFrame: View {
    var screen: UIImage
    var eyebrow: String
    var headline: String
    var statusBar: Color?
    var canvas: CGSize

    private let evening = ThemeCatalog.theme(.midnightToast)
    private let phoneWidth: CGFloat = 340
    private let bezel: CGFloat = 9

    var body: some View {
        ZStack(alignment: .top) {
            evening.paperColor
            VStack(spacing: 14) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(evening.mutedInkColor)
                Text(headline)
                    .font(Typeface.display(38))
                    .displayTracking(38)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(evening.inkColor)
                    .fixedSize()
            }
            .padding(.top, 64)
            phone.padding(.top, 226)
        }
        .frame(width: canvas.width, height: canvas.height)
        .clipped()
    }

    private var phone: some View {
        let s = phoneWidth / canvas.width
        let screenSize = CGSize(width: phoneWidth, height: canvas.height * s)
        let inner = 62 * s
        return ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: inner + bezel, style: .continuous)
                .fill(Color(white: 0.08))
                .overlay(RoundedRectangle(cornerRadius: inner + bezel, style: .continuous)
                    .strokeBorder(Color(white: 0.3), lineWidth: 1))
            deviceScreen
                .scaleEffect(s, anchor: .topLeading)
                .frame(width: screenSize.width, height: screenSize.height, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: inner, style: .continuous))
                .padding(bezel)
            // The Dynamic Island.
            Capsule().fill(.black)
                .frame(width: 126 * s, height: 37 * s)
                .padding(.top, bezel + 11 * s)
        }
        .frame(width: screenSize.width + bezel * 2, height: screenSize.height + bezel * 2)
    }

    /// The captured screen at full size, with a status bar drawn where the app shows one.
    private var deviceScreen: some View {
        ZStack(alignment: .top) {
            Image(uiImage: screen).resizable()
            if let statusBar {
                HStack {
                    Text("9:41")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 140)
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "cellularbars")
                        Image(systemName: "wifi")
                        Image(systemName: "battery.100")
                            .font(.system(size: 17, weight: .regular))
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 140)
                }
                .foregroundStyle(statusBar)
                .padding(.top, 19)
                .padding(.horizontal, 8)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}
