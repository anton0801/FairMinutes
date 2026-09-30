import SwiftUI

enum Segment: String, CaseIterable, Identifiable {
    case match, squad, season

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum DrawerDetent: Int, Comparable {
    case collapsed, medium, full

    static func < (lhs: DrawerDetent, rhs: DrawerDetent) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Panels that open inside the drawer on top of a segment's own content.
enum Route: Equatable {
    case matchSetup
    case summary(UUID)
    case player(UUID)
    case departure(DepartureReason)
    case swap(UUID)
    case move(MovePreview)
    case editPlayer(UUID?)
    case settings
    case format
    case about
    case seasonPlayer(UUID)
    case pastSeason(UUID)
    case newSeason
}

/// Navigation for the one screen the app has: which segment the drawer shows, how far it
/// is pulled up, and what is stacked inside it.
@MainActor
final class ScreenState: ObservableObject {
    @Published var segment: Segment = .match
    @Published var detent: DrawerDetent = .collapsed
    @Published private(set) var stacks: [Segment: [Route]] = [:]
    @Published var selectedPlayer: UUID?

    var route: Route? { stacks[segment]?.last }

    func select(_ segment: Segment) {
        guard segment != self.segment else {
            if detent == .collapsed { withAnimation(Motion.drawer) { detent = .medium } }
            return
        }
        selectedPlayer = nil
        withAnimation(Motion.drawer) {
            self.segment = segment
            if segment != .match && detent == .collapsed { detent = .medium }
        }
    }

    func push(_ route: Route, in segment: Segment? = nil, detent: DrawerDetent = .full) {
        let target = segment ?? self.segment
        withAnimation(Motion.drawer) {
            self.segment = target
            if case .player(let id) = route { selectedPlayer = id } else if case .swap = route {} else { selectedPlayer = nil }
            var stack = stacks[target] ?? []
            // Opening the same kind of panel again replaces it rather than stacking duplicates.
            if let last = stack.last, Self.sameKind(last, route) { stack.removeLast() }
            stack.append(route)
            stacks[target] = stack
            if self.detent < detent { self.detent = detent }
        }
    }

    func pop() {
        withAnimation(Motion.drawer) {
            stacks[segment]?.removeLast()
            if case .player(let id)? = route { selectedPlayer = id } else { selectedPlayer = nil }
            if route == nil && segment == .match && detent == .full { detent = .medium }
        }
    }

    func popToRoot(_ segment: Segment? = nil, detent: DrawerDetent? = nil) {
        withAnimation(Motion.drawer) {
            stacks[segment ?? self.segment] = []
            selectedPlayer = nil
            if let detent { self.detent = detent }
        }
    }

    func reset() {
        stacks = [:]
        segment = .match
        detent = .collapsed
        selectedPlayer = nil
    }

    private static func sameKind(_ a: Route, _ b: Route) -> Bool {
        switch (a, b) {
        case (.player, .player), (.move, .move), (.swap, .swap), (.departure, .departure), (.summary, .summary): return true
        default: return false
        }
    }
}
