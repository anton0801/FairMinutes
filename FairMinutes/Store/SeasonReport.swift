import UIKit

/// Builds the season PDF on the phone. It is only written to a temporary file and handed
/// to the share sheet; where it goes from there is the coach's decision.
enum SeasonReport {
    enum Failure: LocalizedError {
        case nothingToExport
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .nothingToExport: return "There are no players in the squad yet."
            case .writeFailed: return "The PDF could not be created on this phone."
            }
        }
    }

    private static let anchor = UIColor(red: 14 / 255, green: 27 / 255, blue: 61 / 255, alpha: 1)
    private static let blue = UIColor(red: 34 / 255, green: 85 / 255, blue: 224 / 255, alpha: 1)
    private static let red = UIColor(red: 226 / 255, green: 54 / 255, blue: 54 / 255, alpha: 1)
    private static let yellow = UIColor(red: 1, green: 194 / 255, blue: 26 / 255, alpha: 1)
    private static let marking = UIColor(red: 201 / 255, green: 218 / 255, blue: 245 / 255, alpha: 1)

    static func make(teamName: String, season: Season, ledger: SeasonLedger) throws -> URL {
        let rows = ledger.lines
        guard !rows.isEmpty else { throw Failure.nothingToExport }
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 44
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let safeName = season.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Fair Minutes \(safeName).pdf")

        let title = UIFont.systemFont(ofSize: 26, weight: .heavy).italicised
        let heading = UIFont.systemFont(ofSize: 14, weight: .heavy).italicised
        let body = UIFont.systemFont(ofSize: 11, weight: .regular)
        let bold = UIFont.systemFont(ofSize: 11, weight: .bold)
        let small = UIFont.systemFont(ofSize: 9, weight: .regular)
        let insights = ledger.insights

        do {
            try renderer.writePDF(to: url) { context in
                var y: CGFloat = margin
                func newPage() {
                    context.beginPage()
                    y = margin
                    stripes(at: CGPoint(x: margin, y: page.height - 30))
                }
                func text(_ string: String, _ font: UIFont, _ color: UIColor = anchor, x: CGFloat = margin, width: CGFloat? = nil) -> CGFloat {
                    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                    let box = CGRect(x: x, y: y, width: width ?? page.width - margin - x, height: 400)
                    let measured = (string as NSString).boundingRect(with: box.size, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
                    (string as NSString).draw(with: box, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
                    return ceil(measured.height)
                }
                func ensure(_ height: CGFloat) {
                    if y + height > page.height - margin - 20 { newPage() }
                }

                newPage()
                y += text((teamName.isEmpty ? "fair minutes" : teamName).lowercased(), title)
                y += 4
                y += text("Season \(season.name) · \(season.matches.count) \(season.matches.count == 1 ? "match" : "matches") · exported \(Date().formatted(date: .abbreviated, time: .omitted))", body)
                y += 18

                if insights.hasEnoughData {
                    y += text("minutes spread across the squad", heading)
                    y += 2
                    y += text("\(Minutes.whole(insights.spreadSeconds)) minutes between the most and the fewest season minutes. Attendance \(Int((insights.attendanceRate * 100).rounded()))%.", body)
                    y += 16
                } else {
                    y += text("More Matches Needed — three matches are needed to see season balance.", body)
                    y += 16
                }

                y += text("minutes by player — sorted by name", heading)
                y += 8
                let columns: [CGFloat] = [margin, margin + 34, margin + 150, margin + 330, margin + 400]
                _ = text("No.", bold, x: columns[0], width: 30)
                _ = text("Name", bold, x: columns[1], width: 110)
                _ = text("Minutes / share of possible", bold, x: columns[2], width: 170)
                _ = text("Matches", bold, x: columns[3], width: 60)
                y += text("Positions tried", bold, x: columns[4], width: page.width - margin - columns[4])
                y += 6
                for row in rows {
                    ensure(30)
                    let top = y
                    _ = text("\(row.number)", bold, x: columns[0], width: 30)
                    _ = text(row.name, body, x: columns[1], width: 110)
                    let track = CGRect(x: columns[2], y: top + 3, width: 110, height: 6)
                    marking.setFill()
                    UIBezierPath(roundedRect: track, cornerRadius: 3).fill()
                    blue.setFill()
                    UIBezierPath(roundedRect: CGRect(x: track.minX, y: track.minY, width: max(3, track.width * row.share), height: track.height), cornerRadius: 3).fill()
                    _ = text("\(Minutes.whole(row.playedSeconds)) · \(Int((row.share * 100).rounded()))%", small, x: columns[2] + 116, width: 60)
                    _ = text("\(row.matchesAttended) of \(row.matchesTotal)", body, x: columns[3], width: 60)
                    let tried = row.linesTried.map(\.short).joined(separator: " · ")
                    let height = text(tried.isEmpty ? "—" : tried, body, x: columns[4], width: page.width - margin - columns[4])
                    y = top + max(18, height + 6)
                    marking.setStroke()
                    let rule = UIBezierPath()
                    rule.move(to: CGPoint(x: margin, y: y - 3))
                    rule.addLine(to: CGPoint(x: page.width - margin, y: y - 3))
                    rule.lineWidth = 0.5
                    rule.stroke()
                }

                y += 18
                ensure(40)
                y += text("matches", heading)
                y += 6
                if season.matches.isEmpty {
                    y += text("No matches recorded yet.", body)
                }
                for match in season.matches.sorted(by: { $0.date < $1.date }) {
                    ensure(20)
                    let versus = match.opponent.isEmpty ? "Match" : "vs \(match.opponent)"
                    y += text("\(match.date.formatted(date: .abbreviated, time: .omitted)) · \(versus) · \(match.attendees.count) players · \(match.format.playersOnField)-a-side, \(match.format.periods.count) × \(match.format.periodMinutes) min", body)
                    y += 4
                }

                y += 18
                ensure(40)
                y += text("Minutes only. Fair Minutes does not rate, score or compare children by ability. Made on the coach's phone; nothing was uploaded.", small, UIColor(white: 0.35, alpha: 1))
            }
        } catch {
            throw Failure.writeFailed
        }
        return url
    }

    private static func stripes(at origin: CGPoint) {
        for (index, color) in [blue, red, yellow].enumerated() {
            color.setFill()
            UIBezierPath(rect: CGRect(x: origin.x + CGFloat(index) * 26, y: origin.y, width: 22, height: 4)).fill()
        }
    }
}

private extension UIFont {
    var italicised: UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(.traitItalic)) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

/// Presents the system share sheet from whatever is on screen.
enum ShareSheet {
    @MainActor
    static func present(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController ?? scene.windows.first?.rootViewController
        else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 80, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
