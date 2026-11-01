import SwiftUI
import Vision

/// Frames the recipient's photo for the cover: drag and pinch it inside a portrait window.
/// The cover is shown at several shapes (the home card, the Sendoff's header, the reveal, a
/// thumbnail), all close to 3:4, so a 3:4 crop with their face in the middle survives every one.
/// It opens already centred on the faces Vision finds.
struct PhotoFramer: View {
    let image: UIImage
    var onDone: (UIImage) -> Void
    var onCancel: () -> Void

    /// Width over height of the frame and of the saved photo.
    static let aspect: CGFloat = 3 / 4

    /// Zoom on top of the smallest size that fills the frame.
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    /// Where the photo's centre sits, relative to the frame's centre, in points.
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero
    @State private var placed = false

    var body: some View {
        GeometryReader { g in
            let frame = frameSize(in: g.size)
            let shown = shownSize(frame)
            ZStack {
                Color.black
                Image(uiImage: image)
                    .resizable()
                    .frame(width: shown.width, height: shown.height)
                    .offset(offset)
                // Everything outside the frame is dimmed, so the crop reads at a glance.
                Rectangle().fill(.black.opacity(0.6))
                    .mask {
                        Rectangle().overlay {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .frame(width: frame.width, height: frame.height)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .allowsHitTesting(false)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.85), lineWidth: 1)
                    .frame(width: frame.width, height: frame.height)
                    .allowsHitTesting(false)
            }
            .frame(width: g.size.width, height: g.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        offset = clamped(CGSize(width: baseOffset.width + v.translation.width,
                                                height: baseOffset.height + v.translation.height), frame)
                    }
                    .onEnded { _ in baseOffset = offset }
                    .simultaneously(with: MagnifyGesture()
                        .onChanged { v in
                            zoom = min(4, max(1, baseZoom * v.magnification))
                            offset = clamped(offset, frame)
                        }
                        .onEnded { _ in baseZoom = zoom; baseOffset = offset })
            )
            .overlay(alignment: .top) {
                HStack {
                    CircleButton(systemImage: "xmark", label: "Cancel", onImage: true) { onCancel() }
                    Spacer()
                    Eyebrow(text: "Frame the photo", tint: .white.opacity(0.85))
                    Spacer()
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 16) {
                    Text("Drag and pinch so their face sits in the frame.")
                        .font(Typeface.caption).foregroundStyle(.white.opacity(0.75))
                    PrimaryButton(title: "Use this photo") { onDone(cropped(frame)) }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .onAppear {
                guard !placed else { return }
                placed = true
                offset = clamped(faceCentredOffset(shownSize(frame)), frame)
                baseOffset = offset
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden()
    }

    // MARK: Geometry

    /// As large as fits between the controls, keeping 3:4.
    private func frameSize(in size: CGSize) -> CGSize {
        let width = min(size.width - 40, (size.height - 220) * Self.aspect)
        return CGSize(width: width, height: width / Self.aspect)
    }

    /// The photo on screen: just filling the frame at zoom 1.
    private func shownSize(_ frame: CGSize) -> CGSize {
        let fill = max(frame.width / image.size.width, frame.height / image.size.height) * zoom
        return CGSize(width: image.size.width * fill, height: image.size.height * fill)
    }

    /// Keeps the frame covered: the photo's edges never come inside it.
    private func clamped(_ o: CGSize, _ frame: CGSize) -> CGSize {
        let shown = shownSize(frame)
        let maxX = (shown.width - frame.width) / 2, maxY = (shown.height - frame.height) / 2
        return CGSize(width: min(maxX, max(-maxX, o.width)), height: min(maxY, max(-maxY, o.height)))
    }

    /// Moves the faces Vision finds to the middle of the frame. Leaves the photo centred when
    /// there are none.
    private func faceCentredOffset(_ shown: CGSize) -> CGSize {
        guard let cg = image.cgImage else { return .zero }
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cgImage: cg, orientation: .up).perform([request])
        let faces = (request.results ?? []).map(\.boundingBox)
        guard let first = faces.first else { return .zero }
        let all = faces.dropFirst().reduce(first) { $0.union($1) }
        // Vision measures from the bottom left, as fractions of the image.
        let centre = CGPoint(x: all.midX, y: 1 - all.midY)
        return CGSize(width: (0.5 - centre.x) * shown.width, height: (0.5 - centre.y) * shown.height)
    }

    /// The part of the photo inside the frame, at most 1600 pixels tall.
    private func cropped(_ frame: CGSize) -> UIImage {
        let source = Self.cropRect(imageSize: image.size, frame: frame, zoom: zoom, offset: offset)
        guard let cg = image.cgImage?.cropping(to: source) else { return image }
        return CoverPhoto.fitted(UIImage(cgImage: cg), longSide: 1600)
    }

    /// The pixels under the frame, for a photo of `imageSize` pixels shown filling `frame` at
    /// `zoom`, its centre moved by `offset` points from the frame's centre.
    static func cropRect(imageSize: CGSize, frame: CGSize, zoom: CGFloat, offset: CGSize) -> CGRect {
        let fill = max(frame.width / imageSize.width, frame.height / imageSize.height) * zoom
        let shown = CGSize(width: imageSize.width * fill, height: imageSize.height * fill)
        let x = (shown.width - frame.width) / 2 - offset.width
        let y = (shown.height - frame.height) / 2 - offset.height
        return CGRect(x: x / fill, y: y / fill, width: frame.width / fill, height: frame.height / fill).integral
    }
}

/// Library photos arrive as HEIC or full-size JPEG, sometimes rotated by metadata. The cover never
/// needs more than 1600 pixels on the long side, so it is redrawn upright and smaller first.
enum CoverPhoto {
    static func image(from data: Data) -> UIImage? {
        UIImage(data: data).map { fitted($0, longSide: 2400) }
    }

    static func fitted(_ image: UIImage, longSide: CGFloat) -> UIImage {
        let scale = min(1, longSide / max(image.size.width, image.size.height))
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// Saves it as a JPEG in the temporary folder, ready to upload.
    static func jpegFile(_ image: UIImage) -> URL? {
        guard let jpeg = image.jpegData(compressionQuality: 0.82) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        return (try? jpeg.write(to: url)) != nil ? url : nil
    }
}

/// A photo waiting to be framed, for `fullScreenCover(item:)`.
struct PhotoToFrame: Identifiable {
    let id = UUID()
    let image: UIImage
}
