import SwiftUI

/// Rounded only at the top, like a sheet pulled up over the pitch.
struct TopRoundedShape: Shape {
    var radius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Just the top edge of `TopRoundedShape`, for the anchor outline.
private struct TopEdge: Shape {
    var radius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius + 18))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + radius + 18))
        return path
    }
}

/// Lets any part of a panel act as the drawer's drag handle without the drawer having to
/// know what the panel contains.
struct DrawerDrag {
    var changed: (CGFloat) -> Void = { _ in }
    var ended: (CGFloat, CGFloat) -> Void = { _, _ in }
    var toggle: () -> Void = {}
}

private struct DrawerDragKey: EnvironmentKey {
    static let defaultValue = DrawerDrag()
}

extension EnvironmentValues {
    var drawerDrag: DrawerDrag {
        get { self[DrawerDragKey.self] }
        set { self[DrawerDragKey.self] = newValue }
    }
}

private struct DrawerHandle: ViewModifier {
    @Environment(\.drawerDrag) private var drag

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
                    .onChanged { drag.changed($0.translation.height) }
                    .onEnded { drag.ended($0.translation.height, $0.predictedEndTranslation.height) }
            )
    }
}

extension View {
    /// Makes this part of a panel pull the drawer up and down.
    func drawerHandle() -> some View { modifier(DrawerHandle()) }
}

/// The sheet with three resting positions: collapsed (96 pt, the next change), medium
/// (the plan) and full (squad, season, settings). No shadow: an anchor line marks its edge.
struct DrawerContainer<Content: View>: View {
    @Binding var detent: DrawerDetent
    let heights: [DrawerDetent: CGFloat]
    let bottomInset: CGFloat
    @ViewBuilder var content: Content

    @State private var dragOffset: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func height(_ detent: DrawerDetent) -> CGFloat { heights[detent] ?? 96 }

    var body: some View {
        let minimum = height(.collapsed)
        let maximum = height(.full)
        let current = min(maximum, max(minimum, height(detent) - dragOffset))

        VStack(spacing: 0) {
            grabber
            content
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .frame(height: max(0, current - 22), alignment: .top)
                .clipped()
            // The home-indicator strip stays blank so nothing peeks out under the collapsed strip.
            Palette.ground.frame(height: bottomInset)
        }
        .frame(height: current + bottomInset, alignment: .top)
        .background(TopRoundedShape().fill(Palette.ground))
        .overlay(TopEdge().stroke(Palette.anchor, lineWidth: Metric.stroke))
        .environment(\.drawerDrag, DrawerDrag(
            changed: { dragOffset = $0 },
            ended: { settle(translation: $0, predicted: $1) },
            toggle: toggle
        ))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Expand panel")) { move(by: 1) }
        .accessibilityAction(named: Text("Collapse panel")) { move(by: -1) }
    }

    private var grabber: some View {
        Button(action: toggle) {
            Capsule()
                .fill(Palette.anchor.opacity(0.28))
                .frame(width: 44, height: 5)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .drawerHandle()
        .accessibilityLabel(detent == .collapsed ? "Expand panel" : "Collapse panel")
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : Motion.drawer) {
            detent = detent == .collapsed ? .medium : .collapsed
        }
    }

    private func move(by step: Int) {
        let next = DrawerDetent(rawValue: min(2, max(0, detent.rawValue + step))) ?? detent
        withAnimation(reduceMotion ? nil : Motion.drawer) { detent = next }
    }

    private func settle(translation: CGFloat, predicted: CGFloat) {
        let landing = height(detent) - (translation + (predicted - translation) * 0.35)
        let nearest = [DrawerDetent.collapsed, .medium, .full].min { abs(height($0) - landing) < abs(height($1) - landing) } ?? detent
        withAnimation(reduceMotion ? nil : Motion.drawer) {
            detent = nearest
            dragOffset = 0
        }
    }
}
