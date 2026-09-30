import SwiftUI

/// Chooses what the drawer shows: a segment's own panel, or whatever is stacked on it.
struct DrawerContent: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState

    var body: some View {
        VStack(spacing: 0) {
            if let problem = store.saveError {
                Button(action: store.retrySave) {
                    NoteLine(text: "\(problem) Tap to try again.", tint: Palette.red)
                        .padding(.horizontal, Metric.gutter)
                        .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
            }
            content
                .id(key)
                .transition(.opacity)
        }
    }

    private var key: String {
        guard let route = screen.route else { return screen.segment.rawValue }
        return "\(screen.segment.rawValue)-\(String(describing: route))"
    }

    @ViewBuilder
    private var content: some View {
        if let route = screen.route {
            switch route {
            case .matchSetup: MatchSetupPanel()
            case .summary(let id): MatchSummaryPanel(recordID: id)
            case .player(let id): PlayerMatchPanel(playerID: id)
            case .departure(let reason): DeparturePanel(reason: reason)
            case .swap(let id): SwapPanel(playerID: id)
            case .move(let preview): MovePreviewPanel(preview: preview)
            case .editPlayer(let id): PlayerEditorPanel(playerID: id)
            case .settings: SettingsPanel()
            case .format: FormatPanel()
            case .about: AboutPanel()
            case .seasonPlayer(let id): SeasonPlayerPanel(playerID: id)
            case .pastSeason(let id): PastSeasonPanel(seasonID: id)
            case .newSeason: NewSeasonPanel()
            }
        } else {
            switch screen.segment {
            case .match: MatchPanel()
            case .squad: SquadPanel()
            case .season: SeasonPanel()
            }
        }
    }
}

/// Header + scrolling body used by every pushed panel. The header doubles as a drag handle.
struct PanelScaffold<Content: View, Trailing: View>: View {
    let title: String
    var keepsCase = false
    var subtitle: String?
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                if let onBack {
                    BackLink(action: onBack)
                        .padding(.top, -8)
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        ScreenTitle(text: title, size: 28, keepsCase: keepsCase)
                        if let subtitle {
                            Text(subtitle)
                                .font(Typeface.label)
                                .foregroundColor(Palette.muted)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 8)
                    trailing
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 10)
            .drawerHandle()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 4)
                .padding(.bottom, 40)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

extension PanelScaffold where Trailing == EmptyView {
    init(title: String, keepsCase: Bool = false, subtitle: String? = nil, onBack: (() -> Void)? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.keepsCase = keepsCase
        self.subtitle = subtitle
        self.onBack = onBack
        self.trailing = EmptyView()
        self.content = content()
    }
}

/// The strip every segment shows when the drawer is collapsed: two lines of status on the
/// left and the one action that matters on the right.
struct SummaryStrip<Action: View>: View {
    let eyebrow: String
    let headline: String
    var tint: Color = Palette.anchor
    @ViewBuilder var action: Action

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(Typeface.label)
                    .foregroundColor(Palette.muted)
                    .lineLimit(1)
                Text(headline.lowercased())
                    .font(.system(size: Typeface.scaled(21, .title3), weight: .heavy).italic())
                    .foregroundColor(tint)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            action
        }
        .padding(.horizontal, Metric.gutter)
        // Grabber (22) + strip (74) = the 96-point collapsed drawer from the brief.
        .frame(height: 74)
        .drawerHandle()
    }
}
