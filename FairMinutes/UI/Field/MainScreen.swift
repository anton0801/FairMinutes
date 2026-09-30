import SwiftUI

/// The app's only screen: the pitch from above, and the drawer pulled up over it.
struct MainScreen: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var screen = ScreenState()
    @StateObject private var keyboard = KeyboardObserver()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            base
                .ignoresSafeArea(.keyboard)
            drawerLayer
        }
        .environmentObject(screen)
        .onChange(of: store.justFinishedMatchID) { id in
            guard let id else { return }
            screen.popToRoot(.match)
            screen.push(.summary(id), in: .match, detent: .full)
        }
        .onChange(of: scenePhase) { phase in
            // The clock is recomputed from the device time; this only catches up the alerts.
            if phase == .active { store.refreshLiveState() }
        }
        #if DEBUG
        .onAppear(perform: applyDebugLaunchState)
        #endif
    }

    #if DEBUG
    /// Screenshot automation only: `-FMSegment season -FMDetent full -FMRoute settings`.
    private func applyDebugLaunchState() {
        let defaults = UserDefaults.standard
        if let segment = defaults.string(forKey: "FMSegment").flatMap(Segment.init(rawValue:)) { screen.segment = segment }
        switch defaults.string(forKey: "FMDetent") {
        case "medium": screen.detent = .medium
        case "full": screen.detent = .full
        default: break
        }
        let match = store.data.liveMatch
        let firstOnField = match?.lineup.sorted { $0.key < $1.key }.first?.value
        let firstBench = store.squadByName.first { match?.isAvailable($0.id) == true && match?.isOnField($0.id) == false }?.id
        switch defaults.string(forKey: "FMRoute") {
        case "setup": screen.push(.matchSetup)
        case "player": if let id = firstOnField { screen.push(.player(id), detent: .medium) }
        case "summary": if let id = store.season.matches.last?.id { screen.push(.summary(id)) }
        case "editor": screen.push(.editPlayer(nil))
        case "settings": screen.push(.settings)
        case "format": screen.push(.format)
        case "about": screen.push(.about)
        case "seasonPlayer": if let id = store.squadByName.first?.id { screen.push(.seasonPlayer(id)) }
        case "departure": screen.push(.departure(.injury), detent: .medium)
        case "move": if let id = firstBench, let slot = match?.lineup.sorted(by: { $0.key < $1.key }).last?.key, let preview = store.previewMove(id, to: slot) { screen.push(.move(preview), detent: .medium) }
        default: break
        }
    }
    #endif

    // MARK: Pitch side

    private var base: some View {
        VStack(spacing: 0) {
            SegmentBar(selection: screen.segment, onSelect: screen.select)
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 6)
                .frame(height: 58)
            TimelineView(.animation(minimumInterval: 0.2, paused: store.data.liveMatch?.phase != .running)) { context in
                VStack(spacing: 0) {
                    FieldHeader(match: store.data.liveMatch, teamName: store.data.teamName, now: context.date)
                        .padding(.horizontal, Metric.gutter)
                    PitchBoard(
                        match: store.data.liveMatch,
                        squad: store.data.squad,
                        now: context.date,
                        selected: screen.selectedPlayer,
                        emptyMessage: store.data.squad.isEmpty ? "Add players in Squad, then set up a match." : "No match set up yet.",
                        onTap: { id in
                            Haptics.tap()
                            screen.push(.player(id), in: .match, detent: .medium)
                        },
                        onDrop: handleDrop
                    )
                    .padding(.horizontal, Metric.gutter)
                    .padding(.top, 4)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    private func handleDrop(_ id: UUID, _ target: DropTarget) {
        let slot: Int?
        switch target {
        case .slot(let index): slot = index
        case .bench: slot = nil
        }
        guard let preview = store.previewMove(id, to: slot) else { return }
        Haptics.tap()
        screen.push(.move(preview), in: .match, detent: .medium)
    }

    // MARK: Drawer side

    /// The drawer ignores the keyboard's safe area and makes room for it itself: its top
    /// stays put under the segments and the part behind the keyboard becomes blank.
    private var drawerLayer: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            let homeIndicator = proxy.safeAreaInsets.bottom
            let lift = max(0, keyboard.height - homeIndicator)
            let full = height - 62 - lift
            let heights: [DrawerDetent: CGFloat] = [
                .collapsed: min(96, full),
                .medium: min(full, min(height - 70, max(340, height * 0.54))),
                .full: full
            ]
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                DrawerContainer(detent: $screen.detent, heights: heights, bottomInset: homeIndicator + lift) {
                    DrawerContent()
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
        }
        .ignoresSafeArea(.keyboard)
    }
}

/// Tracks how much of the screen the keyboard covers.
final class KeyboardObserver: ObservableObject {
    @Published private(set) var height: CGFloat = 0
    private var tokens: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) { [weak self] note in
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let screen = UIScreen.main.bounds
            withAnimation(Motion.drawer) { self?.height = max(0, screen.maxY - frame.minY) }
        })
        tokens.append(center.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { [weak self] _ in
            withAnimation(Motion.drawer) { self?.height = 0 }
        })
    }

    deinit {
        tokens.forEach(NotificationCenter.default.removeObserver)
    }
}

/// Match · Squad · Season. Switches what the drawer shows; the pitch stays.
struct SegmentBar: View {
    let selection: Segment
    let onSelect: (Segment) -> Void
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Segment.allCases) { segment in
                let chosen = segment == selection
                Button {
                    Haptics.tap()
                    onSelect(segment)
                } label: {
                    Text(segment.title.lowercased())
                        .font(.system(size: Typeface.scaled(17, .headline), weight: .heavy).italic())
                        .foregroundColor(chosen ? .white : Palette.anchor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background {
                            if chosen {
                                ZStack(alignment: .leading) {
                                    Palette.anchor
                                    Palette.yellow.frame(width: 5)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .matchedGeometryEffect(id: "segment", in: namespace)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Palette.anchor, lineWidth: Metric.stroke)
        )
        .animation(Motion.drawer, value: selection)
    }
}

/// Title on the left in heavy italic lower case, the match clock on the right.
struct FieldHeader: View {
    let match: LiveMatch?
    let teamName: String
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(subtitle)
                .font(Typeface.label)
                .foregroundColor(Palette.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .lastTextBaseline, spacing: 12) {
                Text(title)
                    .font(Typeface.title(30))
                    .foregroundColor(Palette.anchor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 4)
                if let match {
                    clock(match)
                }
            }
        }
        .frame(height: 78, alignment: .bottom)
    }

    private var title: String {
        guard let match else { return (teamName.isEmpty ? "fair minutes" : teamName).lowercased() }
        return (match.opponent.isEmpty ? "next match" : "vs \(match.opponent)").lowercased()
    }

    private var subtitle: String {
        guard let match else { return "No match set up" }
        let format = "\(match.format.playersOnField)-a-side · \(match.format.periods.count) × \(match.format.periodMinutes)"
        switch match.phase {
        case .ready: return "\(match.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(format)"
        case .running: return match.periodName
        case .paused: return "\(match.periodName) · paused"
        case .interval: return match.format.periods == .halves ? "Half-time" : "Break before \(match.periodName.lowercased())"
        case .finished: return "Full time"
        }
    }

    @ViewBuilder
    private func clock(_ match: LiveMatch) -> some View {
        let reading = match.nominalClock(at: now) - match.overtime(at: now)
        let overtime = match.overtime(at: now)
        VStack(alignment: .trailing, spacing: -6) {
            if overtime >= 1 {
                Text("+\(Minutes.clock(overtime))")
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .foregroundColor(Palette.red)
            }
            Text(Minutes.clock(reading))
                .font(Typeface.minutes(56))
                .foregroundColor(match.phase == .running ? Palette.anchor : Palette.anchor.opacity(0.4))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Match clock \(Int(reading) / 60) minutes \(Int(reading) % 60) seconds\(overtime >= 1 ? ", plus \(Int(overtime) / 60) minutes added" : "")")
    }
}
