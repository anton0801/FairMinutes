import SwiftUI

/// Pitch lines seen from above, our goal at the bottom: touchlines, halfway line, centre
/// circle and spot, both penalty areas with their arcs, goal areas and corner arcs.
/// Proportions come from a full-size pitch so the drawing reads as a pitch at any size.
struct PitchMarkings: Shape {
    var showsBoxes = true

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1)
        var path = Path()
        path.addRoundedRect(in: r, cornerSize: CGSize(width: 4, height: 4))

        path.move(to: CGPoint(x: r.minX, y: r.midY))
        path.addLine(to: CGPoint(x: r.maxX, y: r.midY))

        let circle = min(r.width, r.height) * 0.135
        path.addEllipse(in: CGRect(x: r.midX - circle, y: r.midY - circle, width: circle * 2, height: circle * 2))
        let spot: CGFloat = 2.5
        path.addEllipse(in: CGRect(x: r.midX - spot, y: r.midY - spot, width: spot * 2, height: spot * 2))

        let corner = min(r.width, r.height) * 0.03
        path.move(to: CGPoint(x: r.minX + corner, y: r.minY))
        path.addArc(center: CGPoint(x: r.minX, y: r.minY), radius: corner, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
        path.move(to: CGPoint(x: r.maxX, y: r.minY + corner))
        path.addArc(center: CGPoint(x: r.maxX, y: r.minY), radius: corner, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.move(to: CGPoint(x: r.minX, y: r.maxY - corner))
        path.addArc(center: CGPoint(x: r.minX, y: r.maxY), radius: corner, startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
        path.move(to: CGPoint(x: r.maxX - corner, y: r.maxY))
        path.addArc(center: CGPoint(x: r.maxX, y: r.maxY), radius: corner, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        guard showsBoxes else { return path }
        for top in [true, false] {
            let boxWidth = r.width * 0.59
            let boxDepth = r.height * 0.157
            let goalWidth = r.width * 0.27
            let goalDepth = r.height * 0.052
            path.addRect(CGRect(x: r.midX - boxWidth / 2, y: top ? r.minY : r.maxY - boxDepth, width: boxWidth, height: boxDepth))
            path.addRect(CGRect(x: r.midX - goalWidth / 2, y: top ? r.minY : r.maxY - goalDepth, width: goalWidth, height: goalDepth))

            // The arc of the penalty area: the part of a circle around the spot that lies
            // outside the box.
            let spotY = top ? r.minY + r.height * 0.105 : r.maxY - r.height * 0.105
            let edge = top ? r.minY + boxDepth : r.maxY - boxDepth
            let rise = abs(edge - spotY)
            guard rise < circle else { continue }
            let a = asin(rise / circle)
            let center = CGPoint(x: r.midX, y: spotY)
            let start = top ? a : .pi + a
            let end = top ? .pi - a : 2 * .pi - a
            path.move(to: CGPoint(x: center.x + circle * cos(start), y: center.y + circle * sin(start)))
            path.addArc(center: center, radius: circle, startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
            path.addEllipse(in: CGRect(x: r.midX - 2, y: spotY - 2, width: 4, height: 4))
        }
        return path
    }
}

/// A pitch with nothing on it — the app's empty state.
struct EmptyPitch: View {
    var width: CGFloat = 120

    var body: some View {
        PitchMarkings()
            .stroke(Palette.marking, lineWidth: Metric.line)
            .background(Palette.pitch)
            .frame(width: width, height: width * 1.4)
            .accessibilityHidden(true)
    }
}
