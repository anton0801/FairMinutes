import SwiftUI

/// A playing shirt seen flat: body, trapezoid sleeves, a scooped neck. Drawn in a
/// 64 × 60 design box and scaled to whatever frame it is given.
struct JerseyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 64
        let sy = rect.height / 60
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(23, 2))
        path.addQuadCurve(to: p(41, 2), control: p(32, 14))
        path.addLine(to: p(48, 3))
        path.addLine(to: p(63.5, 15))
        path.addLine(to: p(57.5, 27.5))
        path.addLine(to: p(52, 22))
        path.addLine(to: p(52, 58))
        path.addLine(to: p(12, 58))
        path.addLine(to: p(12, 22))
        path.addLine(to: p(6.5, 27.5))
        path.addLine(to: p(0.5, 15))
        path.addLine(to: p(16, 3))
        path.closeSubpath()
        return path
    }
}

enum JerseyTone: Equatable {
    case onField
    case bench
    case nextChange
    case awaited
    case away
    case plain

    var fill: Color {
        switch self {
        case .onField: return Palette.blue
        case .bench: return Palette.yellow
        case .nextChange: return Palette.red
        case .awaited, .away, .plain: return Palette.ground
        }
    }

    var accessibilityState: String {
        switch self {
        case .onField: return "on the field"
        case .bench: return "on the bench"
        case .nextChange: return "in the next change"
        case .awaited: return "not here yet"
        case .away: return "not here"
        case .plain: return ""
        }
    }
}

/// The shirt with its white number panel. 64 wide is the field size from the brief;
/// the panel is always 34 × 28 of that box and the number scales with it.
struct JerseyView: View {
    let number: Int
    var tone: JerseyTone = .plain
    var width: CGFloat = 64

    private var scale: CGFloat { width / 64 }
    private var height: CGFloat { width * 60 / 64 }
    private var strokeWidth: CGFloat { width < 40 ? 2 : Metric.stroke }

    var body: some View {
        ZStack(alignment: .topLeading) {
            JerseyShape()
                .fill(tone.fill)
            JerseyShape()
                .stroke(
                    Palette.anchor.opacity(tone == .away ? 0.3 : 1),
                    style: StrokeStyle(lineWidth: strokeWidth, lineJoin: .round, dash: tone == .awaited ? [4, 3] : [])
                )
            Text("\(number)")
                .font(Typeface.number(34 * width / 108))
                .foregroundColor(Palette.anchor.opacity(tone == .away ? 0.35 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: 34 * scale, height: 28 * scale)
                .background(Palette.ground.opacity(tone == .awaited || tone == .away || tone == .plain ? 0 : 1))
                .offset(x: 15 * scale, y: 21 * scale)
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// Four-point line under a shirt, filling blue with minutes played against the target.
struct MinutesBar: View {
    let progress: Double
    var width: CGFloat = 64
    var height: CGFloat = 4
    var tint: Color = Palette.blue

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Palette.marking)
            Capsule()
                .fill(tint)
                .frame(width: max(progress > 0 ? height : 0, width * CGFloat(min(1, max(0, progress)))))
        }
        .frame(width: width, height: height)
        .accessibilityHidden(true)
    }
}

/// A child on the board: shirt, first name, minutes line.
struct PlayerToken: View {
    let player: Player
    var tone: JerseyTone
    var progress: Double?
    var width: CGFloat = 64
    var badge: String?

    var body: some View {
        VStack(spacing: 3) {
            JerseyView(number: player.shirtNumber, tone: tone, width: width)
                .overlay(alignment: .topTrailing) {
                    if let badge {
                        Text(badge)
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundColor(Palette.anchor)
                            .padding(.horizontal, 4)
                            .frame(height: 16)
                            .background(Palette.yellow)
                            .overlay(Rectangle().stroke(Palette.anchor, lineWidth: 1.5))
                            .offset(x: 6, y: -4)
                    }
                }
            Text(player.firstName)
                .font(Typeface.playerName)
                .foregroundColor(Palette.anchor.opacity(tone == .away ? 0.45 : 1))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: width + 18)
            if let progress {
                MinutesBar(progress: progress, width: width * 0.86)
            }
        }
    }
}
