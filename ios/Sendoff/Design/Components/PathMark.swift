import SwiftUI

/// The brand mark: a road that reads as an S, wide in the foreground and vanishing up and to
/// the right. Same geometry as `brand/sendoff-icon.svg`, drawn in a 1024 unit space.
struct PathMark: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 40
    /// Draw on the near-black tile (the app icon) or bare, in the theme's ink.
    var onTile: Bool = true

    var body: some View {
        ZStack {
            if onTile {
                RoundedRectangle(cornerRadius: size * 0.2227, style: .continuous)
                    .fill(Color(red: 0.055, green: 0.055, blue: 0.051))
            }
            RoadShape()
                .fill(onTile ? Color(red: 0.953, green: 0.945, blue: 0.925) : theme.inkColor)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Sendoff")
    }
}

struct RoadShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(100, 1024))
        path.addCurve(to: p(585, 680), control1: p(190, 850), control2: p(480, 800))
        path.addCurve(to: p(470, 405), control1: p(680, 570), control2: p(590, 475))
        path.addCurve(to: p(610, 232), control1: p(395, 360), control2: p(430, 290))
        path.addCurve(to: p(905, 148), control1: p(720, 197), control2: p(820, 170))
        path.addCurve(to: p(690, 248), control1: p(845, 190), control2: p(760, 220))
        path.addCurve(to: p(650, 392), control1: p(560, 302), control2: p(575, 350))
        path.addCurve(to: p(720, 740), control1: p(820, 480), control2: p(830, 630))
        path.addCurve(to: p(650, 1024), control1: p(630, 830), control2: p(625, 920))
        path.closeSubpath()
        return path
    }
}

struct RoadEdgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let k = rect.width / 1024
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * k, y: rect.minY + y * k) }
        var path = Path()
        path.move(to: p(100, 1024))
        path.addCurve(to: p(585, 680), control1: p(190, 850), control2: p(480, 800))
        path.addCurve(to: p(470, 405), control1: p(680, 570), control2: p(590, 475))
        path.addCurve(to: p(610, 232), control1: p(395, 360), control2: p(430, 290))
        path.addCurve(to: p(905, 148), control1: p(720, 197), control2: p(820, 170))
        path.addCurve(to: p(600, 265), control1: p(815, 192), control2: p(690, 222))
        path.addCurve(to: p(515, 410), control1: p(465, 315), control2: p(455, 365))
        path.addCurve(to: p(610, 680), control1: p(625, 485), control2: p(695, 575))
        path.addCurve(to: p(170, 1024), control1: p(515, 800), control2: p(280, 850))
        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 30) {
        PathMark(size: 180)
        PathMark(size: 60)
        PathMark(size: 60, onTile: false).background(Color(red: 0.07, green: 0.13, blue: 0.25))
    }
    .padding()
}
