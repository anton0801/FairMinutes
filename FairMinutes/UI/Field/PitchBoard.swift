import SwiftUI

struct BoardToken: Identifiable {
    let id: UUID
    let player: Player
    /// Centre of the shirt (not of the whole token) in board coordinates.
    let center: CGPoint
    let width: CGFloat
    let tone: JerseyTone
    let progress: Double?
    let wiggle: Bool
    let badge: String?
    let draggable: Bool
    let slot: Int?
}

enum DropTarget: Equatable {
    case slot(Int)
    case bench
}

/// Where everything sits on the board for one moment of the match.
struct BoardLayout {
    static let tokenExtra: CGFloat = 26

    var field: CGRect = .zero
    var bench: CGRect = .zero
    var jerseyWidth: CGFloat = 64
    var slotCenters: [Int: CGPoint] = [:]
    var tokens: [BoardToken] = []
    var emptySlots: [Int] = []
    var signature = ""

    init(size: CGSize, match: LiveMatch?, squad: [Player], now: Date) {
        let byName = squad.sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
        var benchPlayers: [Player] = []
        if let match {
            benchPlayers = byName.filter { match.isAvailable($0.id) && !match.isOnField($0.id) }
                + byName.filter { match.isAwaited($0.id) && match.departures[$0.id] == nil }
        }

        // Bench first: it decides how much height the pitch can have.
        let count = benchPlayers.count
        let gap: CGFloat = 10
        let minimumWidth: CGFloat = 42
        let oneRow = count <= 1 || CGFloat(count) * (minimumWidth + gap) - gap <= size.width
        let perRow = oneRow ? max(1, count) : Int(ceil(Double(count) / 2))
        let rows = count == 0 ? 1 : (oneRow ? 1 : 2)
        let benchCap: CGFloat = size.width > 600 ? 76 : 58
        let benchWidth = min(benchCap, max(minimumWidth, (size.width - CGFloat(perRow - 1) * gap) / CGFloat(max(1, perRow))))
        let benchJerseyHeight = benchWidth * 60 / 64
        let benchHeight = 24 + CGFloat(rows) * (benchJerseyHeight + Self.tokenExtra + 6)

        let fieldHeight = max(160, size.height - benchHeight - 8)
        let fieldWidth = min(size.width, fieldHeight * 0.74)
        field = CGRect(x: (size.width - fieldWidth) / 2, y: 0, width: fieldWidth, height: fieldHeight)
        bench = CGRect(x: 0, y: field.maxY + 8, width: size.width, height: benchHeight)
        jerseyWidth = min(size.width > 600 ? 96 : 72, fieldWidth / 4.8, fieldHeight / 5.4)

        guard let match else { return }
        let formation = match.format.formation
        let jerseyHeight = jerseyWidth * 60 / 64
        for slot in formation.slots {
            var y = field.minY + CGFloat(slot.y) * field.height
            // Keep the keeper's name and minutes line inside the pitch.
            y = min(y, field.maxY - (jerseyHeight / 2 + Self.tokenExtra + 4))
            slotCenters[slot.index] = CGPoint(x: field.minX + CGFloat(slot.x) * field.width, y: y)
        }

        let running = match.isUnderway
        let next = match.nextWindowThisPeriod
        let comingOn = Set(running ? next?.comingOn ?? [] : [])
        let goingOff = Set(running ? next?.goingOff ?? [] : [])
        let wiggling: Set<UUID> = {
            guard match.phase == .running, let next else { return [] }
            return match.secondsUntil(next, at: now) <= 60 ? Set(next.comingOn) : []
        }()

        func progress(_ id: UUID) -> Double? {
            guard match.phase != .ready else { return nil }
            let target = max(60, match.plan.targets[id] ?? 0)
            return match.played(id, at: now) / target
        }

        let playersByID = Dictionary(uniqueKeysWithValues: squad.map { ($0.id, $0) })
        for (slot, id) in match.lineup.sorted(by: { $0.key < $1.key }) {
            guard let player = playersByID[id], let center = slotCenters[slot] else { continue }
            tokens.append(BoardToken(
                id: id, player: player, center: center, width: jerseyWidth,
                tone: goingOff.contains(id) ? .nextChange : .onField,
                progress: progress(id), wiggle: false, badge: nil, draggable: true, slot: slot
            ))
        }
        emptySlots = formation.slots.map(\.index).filter { match.lineup[$0] == nil }

        let totalRowWidth = CGFloat(perRow) * benchWidth + CGFloat(perRow - 1) * gap
        for (index, player) in benchPlayers.enumerated() {
            let row = index / perRow
            let column = index % perRow
            let itemsInRow = min(perRow, count - row * perRow)
            let rowWidth = CGFloat(itemsInRow) * benchWidth + CGFloat(itemsInRow - 1) * gap
            let startX = (size.width - min(rowWidth, totalRowWidth)) / 2
            let x = startX + CGFloat(column) * (benchWidth + gap) + benchWidth / 2
            let y = bench.minY + 24 + CGFloat(row) * (benchJerseyHeight + Self.tokenExtra + 6) + benchJerseyHeight / 2
            let awaited = match.isAwaited(player.id)
            tokens.append(BoardToken(
                id: player.id, player: player, center: CGPoint(x: x, y: y), width: benchWidth,
                tone: awaited ? .awaited : (comingOn.contains(player.id) ? .nextChange : .bench),
                progress: awaited ? nil : progress(player.id),
                wiggle: wiggling.contains(player.id),
                badge: awaited ? match.expectedMinute(player.id).map { "\($0)′" } : nil,
                draggable: !awaited, slot: nil
            ))
        }

        signature = match.lineup.sorted { $0.key < $1.key }.map { "\($0.key):\($0.value)" }.joined(separator: ",")
            + "|" + benchPlayers.map(\.id.uuidString).joined(separator: ",")
    }

    func target(at point: CGPoint) -> DropTarget? {
        let reach = jerseyWidth * 0.75
        if let nearest = slotCenters.min(by: { $0.value.distance(to: point) < $1.value.distance(to: point) }),
           nearest.value.distance(to: point) <= reach {
            return .slot(nearest.key)
        }
        if bench.insetBy(dx: 0, dy: -12).contains(point) { return .bench }
        return nil
    }
}

extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat { hypot(x - other.x, y - other.y) }
}

/// The pitch seen from above with the shirts on it and the bench along its bottom edge.
struct PitchBoard: View {
    let match: LiveMatch?
    let squad: [Player]
    let now: Date
    let selected: UUID?
    let emptyMessage: String
    let onTap: (UUID) -> Void
    let onDrop: (UUID, DropTarget) -> Void

    @State private var dragging: UUID?
    @State private var translation: CGSize = .zero
    @State private var hover: DropTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let layout = BoardLayout(size: proxy.size, match: match, squad: squad, now: now)
            ZStack(alignment: .topLeading) {
                pitch(layout)
                benchStrip(layout)
                ForEach(layout.emptySlots, id: \.self) { slot in
                    if let center = layout.slotCenters[slot] {
                        emptySlot(width: layout.jerseyWidth, highlighted: hover == .slot(slot))
                            .position(center)
                    }
                }
                ForEach(layout.tokens) { token in
                    tokenView(token, layout: layout)
                }
            }
            .coordinateSpace(name: "board")
            .animation(reduceMotion ? nil : Motion.substitution, value: layout.signature)
        }
    }

    // MARK: Pitch and bench

    private func pitch(_ layout: BoardLayout) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.pitch)
            PitchMarkings().stroke(Palette.marking, lineWidth: Metric.line)
        }
        .frame(width: layout.field.width, height: layout.field.height)
        .position(x: layout.field.midX, y: layout.field.midY)
        .accessibilityHidden(true)
    }

    private func benchStrip(_ layout: BoardLayout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("bench")
                    .font(.system(size: 13, weight: .heavy).italic())
                    .foregroundColor(Palette.anchor)
                Palette.marking.frame(height: Metric.line)
            }
            .frame(height: 20)
            if match == nil {
                Text(emptyMessage)
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .padding(.top, 6)
            } else if match != nil && layout.tokens.allSatisfy({ $0.slot != nil }) {
                Text("Everyone who is here is on the field.")
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .padding(.top, 6)
            }
            Spacer(minLength: 0)
        }
        .frame(width: layout.bench.width, height: layout.bench.height, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hover == .bench ? Palette.yellow.opacity(0.18) : Color.clear)
        )
        .position(x: layout.bench.midX, y: layout.bench.midY)
    }

    private func emptySlot(width: CGFloat, highlighted: Bool) -> some View {
        JerseyShape()
            .stroke(highlighted ? Palette.blue : Palette.marking, style: StrokeStyle(lineWidth: Metric.stroke, lineJoin: .round, dash: [5, 4]))
            .frame(width: width, height: width * 60 / 64)
            .accessibilityLabel("Empty place")
    }

    // MARK: Tokens

    @ViewBuilder
    private func tokenView(_ token: BoardToken, layout: BoardLayout) -> some View {
        let isDragging = dragging == token.id
        let jerseyHeight = token.width * 60 / 64
        // The token is laid out around the shirt's centre, so shift by the name and bar below it.
        let tokenCenter = CGPoint(x: token.center.x, y: token.center.y + BoardLayout.tokenExtra / 2)

        WiggleWrapper(active: token.wiggle && !reduceMotion) {
            PlayerToken(player: token.player, tone: token.tone, progress: token.progress, width: token.width, badge: token.badge)
        }
        .overlay(alignment: .top) {
            if selected == token.id {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.anchor, lineWidth: Metric.stroke)
                    .frame(width: token.width + 14, height: jerseyHeight + BoardLayout.tokenExtra + 12)
                    .offset(y: -6)
            }
        }
        .hoverRing(hover == .slot(token.slot ?? -1) && dragging != nil && dragging != token.id, width: token.width)
        .scaleEffect(isDragging ? 1.12 : 1)
        .contentShape(Rectangle())
        // Gestures go on before `position`, which would otherwise stretch the hit area
        // over the whole board.
        .onTapGesture { onTap(token.id) }
        .gesture(dragGesture(for: token, layout: layout), including: token.draggable ? .all : .subviews)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(token))
        .accessibilityHint(token.draggable ? "Opens this player's minutes and actions." : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap(token.id) }
        .position(tokenCenter)
        .offset(isDragging ? translation : .zero)
        .zIndex(isDragging ? 10 : (token.slot == nil ? 1 : 2))
    }

    private func dragGesture(for token: BoardToken, layout: BoardLayout) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named("board"))
            .onChanged { value in
                if dragging == nil { dragging = token.id }
                translation = value.translation
                let point = CGPoint(x: token.center.x + value.translation.width, y: token.center.y + value.translation.height)
                let target = layout.target(at: point)
                if target != hover { hover = target }
            }
            .onEnded { value in
                let point = CGPoint(x: token.center.x + value.translation.width, y: token.center.y + value.translation.height)
                let target = layout.target(at: point)
                withAnimation(reduceMotion ? nil : Motion.substitution) {
                    dragging = nil
                    translation = .zero
                    hover = nil
                }
                guard let target else { return }
                switch target {
                case .slot(let slot) where slot == token.slot: return
                case .bench where token.slot == nil: return
                default: onDrop(token.id, target)
                }
            }
    }

    private func accessibilityLabel(_ token: BoardToken) -> String {
        var parts = ["\(token.player.firstName), number \(token.player.shirtNumber)", token.tone.accessibilityState]
        if let match, let target = match.plan.targets[token.id], match.phase != .ready {
            parts.append("\(Minutes.whole(match.played(token.id, at: now))) of \(Minutes.whole(target)) minutes")
        }
        if let badge = token.badge { parts.append("due at \(badge)") }
        return parts.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

private extension View {
    func hoverRing(_ active: Bool, width: CGFloat) -> some View {
        overlay(alignment: .top) {
            if active {
                JerseyShape()
                    .stroke(Palette.blue, style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                    .frame(width: width + 10, height: (width + 10) * 60 / 64)
                    .offset(y: -5)
            }
        }
    }
}

/// A small sway once a second: this child goes on at the next window.
private struct WiggleWrapper<Content: View>: View {
    let active: Bool
    @ViewBuilder var content: Content

    var body: some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let phase = t - floor(t)
                let window = 0.45
                let angle = phase < window ? 7 * sin(phase / window * 4 * .pi) * (1 - phase / window) : 0
                content.rotationEffect(.degrees(angle), anchor: .top)
            }
        } else {
            content
        }
    }
}
