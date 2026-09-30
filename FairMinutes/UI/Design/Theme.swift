import SwiftUI
import UIKit

/// Three kit colours, a white ground, a pale pitch and one dark anchor. Colour always
/// describes a child's state — on the field, on the bench, next to change — never ability.
enum Palette {
    static let ground = Color(hex: 0xFFFFFF)
    static let pitch = Color(hex: 0xF2F7FF)
    static let marking = Color(hex: 0xC9DAF5)
    static let anchor = Color(hex: 0x0E1B3D)
    static let blue = Color(hex: 0x2255E0)
    static let red = Color(hex: 0xE23636)
    static let yellow = Color(hex: 0xFFC21A)

    /// Secondary text: the anchor at a strength that still clears 4.5:1 on white.
    static let muted = Color(hex: 0x0E1B3D).opacity(0.66)
    static let faint = Color(hex: 0x0E1B3D).opacity(0.12)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// SF Pro throughout: Heavy Italic lower-case for titles, Black for shirt numbers,
/// Heavy tabular figures for minutes, Text Bold for names.
enum Typeface {
    /// Sizes follow the reader's text size setting, within the root's cap.
    static func scaled(_ size: CGFloat, _ style: UIFont.TextStyle = .body) -> CGFloat {
        UIFontMetrics(forTextStyle: style).scaledValue(for: size)
    }

    static func title(_ size: CGFloat = 32) -> Font { .system(size: scaled(size, .title1), weight: .heavy).italic() }
    static func heading(_ size: CGFloat = 22) -> Font { .system(size: scaled(size, .title2), weight: .heavy).italic() }
    static func number(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .black) }
    static func minutes(_ size: CGFloat = 56) -> Font { .system(size: size, weight: .heavy).monospacedDigit() }
    static let playerName = Font.system(size: 13, weight: .bold)
    static var body: Font { .system(size: scaled(16)) }
    static var bodyBold: Font { .system(size: scaled(16), weight: .semibold) }
    static var label: Font { .system(size: scaled(13, .footnote), weight: .semibold) }
    static var caption: Font { .system(size: scaled(12, .caption1), weight: .medium) }
    static var button: Font { .system(size: scaled(19, .headline), weight: .heavy).italic() }
    static var smallButton: Font { .system(size: scaled(16, .headline), weight: .heavy).italic() }
}

enum Motion {
    /// The substitution spring from the brief: stiffness 260, damping 20.
    static let substitution = Animation.interpolatingSpring(stiffness: 260, damping: 20)
    static let drawer = Animation.interpolatingSpring(stiffness: 300, damping: 30)
    static let quick = Animation.easeOut(duration: 0.18)
}

enum Metric {
    static let gutter: CGFloat = 16
    static let stroke: CGFloat = 2.5
    static let line: CGFloat = 2
    static let buttonHeight: CGFloat = 58
    static let buttonRadius: CGFloat = 16
    static let fieldRadius: CGFloat = 14
}

/// The accent: three short bars in the kit colours.
struct KitStripes: View {
    var width: CGFloat = 16
    var height: CGFloat = 4

    var body: some View {
        HStack(spacing: 3) {
            Palette.blue.frame(width: width, height: height)
            Palette.red.frame(width: width, height: height)
            Palette.yellow.frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }
}

/// Lower-case heavy italic heading with the kit stripe under it.
struct SectionHeading: View {
    let text: String
    var detail: String?

    init(_ text: String, detail: String? = nil) {
        self.text = text
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(text.lowercased())
                    .font(Typeface.heading())
                    .foregroundColor(Palette.anchor)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(Typeface.label)
                        .foregroundColor(Palette.muted)
                }
            }
            KitStripes(width: 12, height: 3)
        }
    }
}

struct ScreenTitle: View {
    let text: String
    var size: CGFloat = 32
    /// Children's names keep their capitals; every other title is lower case.
    var keepsCase = false

    var body: some View {
        Text(keepsCase ? text : text.lowercased())
            .font(Typeface.title(size))
            .foregroundColor(Palette.anchor)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .accessibilityAddTraits(.isHeader)
    }
}
