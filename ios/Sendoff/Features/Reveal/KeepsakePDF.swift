import SwiftUI
import UIKit

/// The keepsake as a PDF: a cover page, then every entry in reveal order, as the web's printed
/// sheet lays it out (`printKeepsake` in web/app/src/pages/open.ts). Included on every plan; a
/// Free Sendoff ends with the "Made with Sendoff" line, a paid one doesn't.
enum KeepsakePDF {
    static func make(sendoff s: Sendoff, entries: [Contribution]) async throws -> URL {
        var sources = entries.flatMap(\.photos).compactMap { $0.localURL ?? $0.url }
        if let cover = s.recipientPhotoURL { sources.append(cover) }
        let images = await load(sources)
        let data = Layout(page: pageSize, sendoff: s, entries: entries, images: images).render()
        let name = "Sendoff for \(s.recipientName)".replacingOccurrences(of: "/", with: "-")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).pdf")
        try data.write(to: file)
        return file
    }

    /// Letter where it is the paper people print on, A4 everywhere else.
    static var pageSize: CGSize {
        ["US", "CA", "MX", "PH"].contains(Locale.current.region?.identifier ?? "")
            ? CGSize(width: 612, height: 792) : CGSize(width: 595, height: 842)
    }

    /// Photos fetched together, each redrawn no larger than the page needs.
    private static func load(_ urls: [URL]) async -> [URL: UIImage] {
        await withTaskGroup(of: (URL, UIImage?).self) { group in
            for url in Set(urls) {
                group.addTask {
                    let data = url.isFileURL ? try? Data(contentsOf: url) : try? await URLSession.shared.data(from: url).0
                    return (url, data.flatMap(UIImage.init(data:)).map { CoverPhoto.fitted($0, longSide: 1600) })
                }
            }
            var out: [URL: UIImage] = [:]
            for await (url, image) in group { out[url] = image }
            return out
        }
    }
}

/// Lays the keepsake out top to bottom, starting a page whenever the next piece won't fit.
/// Long notes continue onto the next page rather than being cut.
private struct Layout {
    let page: CGSize
    let sendoff: Sendoff
    let entries: [Contribution]
    let images: [URL: UIImage]

    private let margin: CGFloat = 60
    private var width: CGFloat { page.width - margin * 2 }
    private var bottom: CGFloat { page.height - margin }

    func render() -> Data {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: page))
        return renderer.pdfData { ctx in
            var pen = Pen(layout: self, ctx: ctx)
            pen.newPage()
            cover(&pen)
            if !entries.isEmpty { pen.newPage() }
            for (i, e) in entries.enumerated() {
                if i > 0 { pen.space(36) }
                entry(e, &pen)
            }
            pen.space(40)
            let last = "Opened \((sendoff.openedAt ?? .now).formatted(date: .long, time: .omitted))."
                + (sendoff.plan == .free ? " Made with Sendoff." : "")
            pen.text(Self.caption(last))
        }
    }

    private func cover(_ pen: inout Pen) {
        if let url = sendoff.recipientPhotoURL, let photo = images[url] {
            let height = min(width * 4 / 3, page.height * 0.5)
            pen.image(photo, fill: CGSize(width: width, height: height))
            pen.space(32)
        } else {
            pen.space(page.height * 0.22)
        }
        pen.text(Self.eyebrow(sendoff.occasion.title))
        pen.space(10)
        pen.text(Self.serif("For \(sendoff.recipientName)", size: 34))
        if let from = sendoff.fromLine, !from.isEmpty {
            pen.space(8)
            pen.text(Self.sans(from, size: 13, color: .darkGray))
        }
        if let message = sendoff.coverMessage, !message.isEmpty {
            pen.space(22)
            pen.text(Self.serif(message, size: 15))
        }
    }

    private func entry(_ e: Contribution, _ pen: inout Pen) {
        for photo in e.photos {
            guard let url = photo.localURL ?? photo.url, let image = images[url] else { continue }
            pen.image(image, fit: CGSize(width: width, height: 320))
            pen.space(14)
        }
        if let voice = e.voice {
            if let t = voice.transcript, !t.isEmpty {
                pen.text(Self.serif("\u{201C}\(t)\u{201D}", size: 15))
            } else {
                pen.text(Self.caption("Voice note from \(e.authorName). Listen to it at the link."))
            }
            pen.space(12)
        }
        if e.video != nil {
            pen.text(Self.caption("Video from \(e.authorName). Watch it at the link."))
            pen.space(12)
        }
        if let body = e.body, e.hasText {
            pen.text(Self.serif(body, size: 15))
            pen.space(12)
        }
        // Keep the signature with the words above it when the page is nearly full.
        pen.text(Self.signature(e), keepTogether: true)
    }

    // MARK: Type

    private static let ink = UIColor(white: 0.08, alpha: 1)

    static func serif(_ s: String, size: CGFloat) -> NSAttributedString {
        let base = UIFont.systemFont(ofSize: size)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        let p = NSMutableParagraphStyle()
        p.lineSpacing = size * 0.3
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink, .paragraphStyle: p])
    }

    static func sans(_ s: String, size: CGFloat, color: UIColor = ink, weight: UIFont.Weight = .regular, kern: CGFloat = 0) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color, .kern: kern])
    }

    static func eyebrow(_ s: String) -> NSAttributedString { sans(s.uppercased(), size: 10, color: .gray, weight: .semibold, kern: 1.6) }
    static func caption(_ s: String) -> NSAttributedString { sans(s, size: 11, color: .gray) }

    static func signature(_ e: Contribution) -> NSAttributedString {
        let s = NSMutableAttributedString(attributedString: sans("\u{2014} \(e.authorName)", size: 12, weight: .semibold))
        if let rel = e.authorRelationship, !rel.isEmpty { s.append(sans(" \u{00B7} \(rel)", size: 12, color: .gray)) }
        return s
    }

    // MARK: Pen

    /// Where the next piece goes, and the page it goes on.
    struct Pen {
        let layout: Layout
        let ctx: UIGraphicsPDFRendererContext
        var y: CGFloat = 0
        var pageNumber = 0

        mutating func newPage() {
            ctx.beginPage()
            pageNumber += 1
            y = layout.margin
            if pageNumber > 1 {
                let n = Layout.caption("\(pageNumber)")
                let size = n.size()
                n.draw(at: CGPoint(x: (layout.page.width - size.width) / 2, y: layout.page.height - layout.margin / 2 - size.height / 2))
            }
        }

        mutating func space(_ h: CGFloat) {
            y += h
            if y > layout.bottom { newPage() }
        }

        /// Scaled to fit inside `fit`, left aligned, rounded like the app's photos.
        mutating func image(_ image: UIImage, fit: CGSize) {
            let scale = min(fit.width / image.size.width, fit.height / image.size.height, 1)
            draw(image, in: CGSize(width: image.size.width * scale, height: image.size.height * scale), fill: false)
        }

        /// Cropped to exactly `fill`, centred a quarter of the way down like every cover in the app.
        mutating func image(_ image: UIImage, fill: CGSize) {
            draw(image, in: fill, fill: true)
        }

        private mutating func draw(_ image: UIImage, in size: CGSize, fill: Bool) {
            if y + size.height > layout.bottom { newPage() }
            let box = CGRect(x: layout.margin, y: y, width: size.width, height: size.height)
            let cg = ctx.cgContext
            cg.saveGState()
            UIBezierPath(roundedRect: box, cornerRadius: 12).addClip()
            if fill {
                let scale = max(box.width / image.size.width, box.height / image.size.height)
                let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: box.midX - drawn.width / 2, y: box.minY - (drawn.height - box.height) * 0.25,
                                      width: drawn.width, height: drawn.height))
            } else {
                image.draw(in: box)
            }
            cg.restoreGState()
            y += size.height
        }

        /// Wraps to the text width and carries on over as many pages as it needs.
        mutating func text(_ s: NSAttributedString, keepTogether: Bool = false) {
            let storage = NSTextStorage(attributedString: s)
            let manager = NSLayoutManager()
            storage.addLayoutManager(manager)
            let lineHeight = (s.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)?.lineHeight ?? 16
            if layout.bottom - y < lineHeight * (keepTogether ? 3 : 1.5) { newPage() }
            var laidOut = 0
            while laidOut < manager.numberOfGlyphs {
                let container = NSTextContainer(size: CGSize(width: layout.width, height: layout.bottom - y))
                container.lineFragmentPadding = 0
                manager.addTextContainer(container)
                let range = manager.glyphRange(for: container)
                if range.length == 0 { newPage(); continue }
                manager.drawGlyphs(forGlyphRange: range, at: CGPoint(x: layout.margin, y: y))
                y += manager.usedRect(for: container).height
                laidOut = NSMaxRange(range)
                if laidOut < manager.numberOfGlyphs { newPage() }
            }
        }
    }
}

/// The system share sheet, for a file the app has just made: Save to Files, Print, Mail, AirDrop.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A file waiting to be shared, for `sheet(item:)`.
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
}
