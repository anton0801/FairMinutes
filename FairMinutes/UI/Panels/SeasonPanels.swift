import SwiftUI

/// The season: balance first, then one line per child in name order, then the matches.
struct SeasonPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState

    var body: some View {
        let season = store.season
        let insights = store.ledger.insights
        VStack(spacing: 0) {
            SummaryStrip(
                eyebrow: "Season \(season.name) · \(season.matches.count) \(season.matches.count == 1 ? "match" : "matches")",
                headline: insights.hasEnoughData ? "spread \(Minutes.whole(insights.spreadSeconds)) min" : "\(season.matches.count) of \(SeasonInsights.matchesNeeded) matches"
            ) {
                IconButton(systemImage: "gearshape.fill", label: "Settings") { screen.push(.settings) }
            }
            ScrollView {
                SeasonOverview(season: season, isCurrent: true)
                    .padding(.horizontal, Metric.gutter)
                    .padding(.bottom, 40)
            }
        }
    }
}

struct PastSeasonPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let seasonID: UUID

    var body: some View {
        if let season = store.data.seasons.first(where: { $0.id == seasonID }) {
            PanelScaffold(title: "season \(season.name)", subtitle: "\(season.matches.count) matches · finished", onBack: screen.pop) {
                SeasonOverview(season: season, isCurrent: false)
            }
        } else {
            PanelScaffold(title: "season", onBack: screen.pop) {
                ListStateView(phase: .failed("This season is no longer on this phone."), emptyTitle: "", emptyMessage: "", retry: screen.pop) { EmptyView() }
            }
        }
    }
}

struct SeasonOverview: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let season: Season
    let isCurrent: Bool
    @State private var export: ExportState = .idle

    enum ExportState: Equatable {
        case idle, working
        case failed(String)
    }

    var body: some View {
        let ledger = SeasonLedger(season: season, squad: store.data.squad)
        let insights = ledger.insights
        VStack(alignment: .leading, spacing: 22) {
            if store.loadState == .loading {
                LoadingShirts()
            } else if season.matches.isEmpty {
                ListStateView(
                    phase: .empty,
                    emptyTitle: "No matches yet",
                    emptyMessage: "Season minutes appear here after the first full-time whistle."
                ) { EmptyView() }
            } else {
                insightBlock(insights)
                playerLines(ledger)
                matchList
            }
            if isCurrent {
                exportBlock(ledger)
                earlierSeasons
            }
        }
    }

    // MARK: Insights

    @ViewBuilder
    private func insightBlock(_ insights: SeasonInsights) -> some View {
        if !insights.hasEnoughData {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading("more matches needed")
                Text("Three matches are needed to see season balance.")
                    .font(Typeface.body)
                    .foregroundColor(Palette.anchor)
                HStack(spacing: 12) {
                    ForEach(0..<SeasonInsights.matchesNeeded, id: \.self) { index in
                        JerseyView(number: index + 1, tone: index < insights.matchesPlayed ? .onField : .awaited, width: 40)
                    }
                    Text("\(insights.matchesPlayed) of \(SeasonInsights.matchesNeeded)")
                        .font(Typeface.bodyBold)
                        .foregroundColor(Palette.muted)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(insights.matchesPlayed) of \(SeasonInsights.matchesNeeded) matches recorded")
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading("season balance")
                VStack(alignment: .leading, spacing: 0) {
                    Text("Minutes Spread Across the Squad")
                        .font(Typeface.label)
                        .foregroundColor(Palette.muted)
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(Minutes.whole(insights.spreadSeconds))")
                            .font(Typeface.minutes())
                            .foregroundColor(Palette.anchor)
                        Text("min")
                            .font(Typeface.heading(20))
                            .foregroundColor(Palette.anchor)
                    }
                    Text("Between the most and the fewest season minutes in the squad. The closer to zero, the fairer.")
                        .font(Typeface.caption)
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                statLine(
                    title: "Players Below Season Average",
                    value: "\(insights.belowAverage.count)",
                    detail: insights.belowAverage.isEmpty ? "Everyone is at or above the average of \(Minutes.whole(insights.averageSeconds)) min." : "\(FairTimeEngine.listed(insights.belowAverage)) — the next plans give them up to \(Int((store.data.settings.seasonAdjustmentLimit * 100).rounded()))% more.",
                    tint: insights.belowAverage.isEmpty ? Palette.blue : Palette.red
                )
                statLine(
                    title: "Positions Tried",
                    value: String(format: "%.1f", insights.averageLinesTried),
                    detail: "Lines tried per child, out of 4.\(insights.onlyOneLine > 0 ? " \(insights.onlyOneLine) \(insights.onlyOneLine == 1 ? "child has" : "children have") played only one." : "")",
                    tint: Palette.yellow
                )
                statLine(
                    title: "Matches Attended",
                    value: "\(Int((insights.attendanceRate * 100).rounded()))%",
                    detail: "Of all places across \(insights.matchesPlayed) matches.",
                    tint: Palette.blue
                )
            }
        }
    }

    private func statLine(title: String, value: String, detail: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            tint.frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(Typeface.bodyBold)
                        .foregroundColor(Palette.anchor)
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.system(size: Typeface.scaled(24, .title2), weight: .heavy).monospacedDigit())
                        .foregroundColor(Palette.anchor)
                }
                Text(detail)
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    // MARK: Players

    private func playerLines(_ ledger: SeasonLedger) -> some View {
        let lines = ledger.lines
        return VStack(alignment: .leading, spacing: 4) {
            SectionHeading("minutes by player", detail: "sorted by name")
            ListStateView(phase: lines.isEmpty ? .empty : .ready, emptyTitle: "No players", emptyMessage: "The squad is empty.") {
                ForEach(lines) { line in
                    Button {
                        screen.push(.seasonPlayer(line.id), detent: .full)
                    } label: {
                        SeasonRow(line: line)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("The line shows the share of minutes each child could have played in the matches they came to.")
                .font(Typeface.caption)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private var matchList: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeading("matches")
            ForEach(season.matches.sorted { $0.date > $1.date }) { match in
                LinkRow(
                    title: match.opponent.isEmpty ? "Match" : "vs \(match.opponent)",
                    value: "\(match.date.formatted(.dateTime.day().month(.abbreviated))) · \(match.attendees.count) played"
                ) {
                    screen.push(.summary(match.id), detent: .full)
                }
            }
        }
    }

    // MARK: Export and history

    private func exportBlock(_ ledger: SeasonLedger) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .failed(let message) = export {
                NoteLine(text: message, tint: Palette.red)
            }
            SecondaryButton(
                title: export == .working ? "preparing pdf…" : "export season as pdf",
                systemImage: "doc.richtext",
                height: 48,
                isEnabled: export != .working && !store.data.squad.isEmpty
            ) {
                runExport(ledger)
            }
            Text("The PDF is made on this phone and goes only where you send it.")
                .font(Typeface.caption)
                .foregroundColor(Palette.muted)
        }
    }

    private func runExport(_ ledger: SeasonLedger) {
        export = .working
        DispatchQueue.main.async {
            do {
                let url = try SeasonReport.make(teamName: store.data.teamName, season: season, ledger: ledger)
                export = .idle
                ShareSheet.present([url])
            } catch {
                export = .failed(error.localizedDescription)
            }
        }
    }

    @ViewBuilder
    private var earlierSeasons: some View {
        let earlier = store.data.seasons.dropLast().reversed()
        if !earlier.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeading("earlier seasons")
                ForEach(Array(earlier)) { past in
                    LinkRow(title: past.name, value: "\(past.matches.count) matches") {
                        screen.push(.pastSeason(past.id), detent: .full)
                    }
                }
            }
        }
    }
}

/// One child's season as a single horizontal line.
struct SeasonRow: View {
    let line: SeasonLine

    var body: some View {
        HStack(spacing: 10) {
            JerseyView(number: line.number, tone: .plain, width: 32)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(line.name)
                        .font(Typeface.bodyBold)
                        .foregroundColor(Palette.anchor)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text("\(Minutes.whole(line.playedSeconds)) min")
                        .font(.system(size: Typeface.scaled(16), weight: .heavy).monospacedDigit())
                        .foregroundColor(Palette.anchor)
                }
                GeometryReader { proxy in
                    MinutesBar(progress: line.share, width: proxy.size.width, height: 6)
                }
                .frame(height: 6)
                Text("\(line.matchesAttended) of \(line.matchesTotal) matches · \(Int((line.share * 100).rounded()))% of possible · \(line.linesTried.isEmpty ? "no positions yet" : line.linesTried.map(\.short).joined(separator: " "))")
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Palette.marking.frame(height: Metric.line) }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SeasonPlayerPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let playerID: UUID

    var body: some View {
        if let player = store.player(playerID) {
            let line = store.ledger.line(for: player)
            PanelScaffold(title: player.firstName, keepsCase: true, subtitle: "Season \(store.season.name)", onBack: screen.pop) {
                JerseyView(number: player.shirtNumber, tone: .bench, width: 64)
            } content: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text("\(Minutes.whole(line.playedSeconds))")
                            .font(Typeface.minutes())
                            .foregroundColor(Palette.anchor)
                        Text("minutes this season")
                            .font(Typeface.bodyBold)
                            .foregroundColor(Palette.muted)
                    }
                    GeometryReader { proxy in
                        MinutesBar(progress: line.share, width: proxy.size.width, height: 6)
                    }
                    .frame(height: 6)
                    Text("\(Int((line.share * 100).rounded()))% of the minutes \(player.firstName) could have played · \(line.matchesAttended) of \(line.matchesTotal) matches")
                        .font(Typeface.body)
                        .foregroundColor(Palette.anchor)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: 6) {
                    SectionHeading("positions")
                    let tried = PitchLine.allCases.filter { (line.lineSeconds[$0] ?? 0) >= 30 }
                    if tried.isEmpty {
                        Text("No positions recorded yet.")
                            .font(Typeface.body)
                            .foregroundColor(Palette.muted)
                    } else {
                        ForEach(tried) { pitchLine in
                            HStack {
                                Text(pitchLine.title).font(Typeface.bodyBold).foregroundColor(Palette.anchor)
                                Spacer()
                                Text(Minutes.short(line.lineSeconds[pitchLine] ?? 0)).font(Typeface.body).foregroundColor(Palette.anchor)
                            }
                            .frame(minHeight: 32)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    SectionHeading("match by match")
                    let entries = store.season.matches.sorted { $0.date > $1.date }.compactMap { match in
                        match.entries.first(where: { $0.playerID == playerID }).map { (match, $0) }
                    }
                    ListStateView(phase: entries.isEmpty ? .empty : .ready, emptyTitle: "No matches yet", emptyMessage: "Minutes appear after the first full-time whistle.") {
                        ForEach(entries, id: \.0.id) { match, entry in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(match.opponent.isEmpty ? "Match" : "vs \(match.opponent)")
                                        .font(Typeface.bodyBold)
                                        .foregroundColor(Palette.anchor)
                                    Text(match.date.formatted(date: .abbreviated, time: .omitted))
                                        .font(Typeface.caption)
                                        .foregroundColor(Palette.muted)
                                }
                                Spacer()
                                if entry.attended {
                                    Text("\(Minutes.whole(entry.playedSeconds)) min")
                                        .font(.system(size: Typeface.scaled(16), weight: .heavy).monospacedDigit())
                                        .foregroundColor(Palette.anchor)
                                    DeviationChip(seconds: entry.deviationSeconds)
                                } else {
                                    Text("not here")
                                        .font(Typeface.caption)
                                        .foregroundColor(Palette.muted)
                                }
                            }
                            .frame(minHeight: 48)
                            .overlay(alignment: .bottom) { Palette.marking.frame(height: Metric.line) }
                        }
                    }
                }
                PrimaryButton(title: "share with the family", systemImage: "square.and.arrow.up") {
                    ShareSheet.present([ParentSummary.season(store.season, line: line, teamName: store.data.teamName)])
                }
                Text("Only \(player.firstName)'s own minutes are shared — no other child appears.")
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
            }
        } else {
            PanelScaffold(title: "player", onBack: screen.pop) {
                ListStateView(phase: .failed("This player is no longer in the squad."), emptyTitle: "", emptyMessage: "", retry: screen.pop) { EmptyView() }
            }
        }
    }
}

struct NewSeasonPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    @State private var name = ""

    var body: some View {
        let blocked = store.data.liveMatch?.isUnderway == true
        PanelScaffold(title: "new season", subtitle: "Current: \(store.season.name)", onBack: screen.pop) {
            Text("The squad, match format and settings carry over. \(store.season.name) stays in the history with all its matches, and the season balance starts again from zero.")
                .font(Typeface.body)
                .foregroundColor(Palette.anchor)
                .fixedSize(horizontal: false, vertical: true)
            LabeledField(label: "Season Name") {
                OutlinedTextField(placeholder: AppStore.seasonName(for: Date()), text: $name, capitalization: .never)
            }
            if blocked {
                NoteLine(text: "A match is being played. Finish it first.", tint: Palette.red)
            }
            PrimaryButton(title: "start new season", systemImage: "arrow.triangle.2.circlepath", isEnabled: !blocked) {
                store.startNewSeason(named: name)
                screen.popToRoot(.season, detent: .medium)
            }
        }
        .onAppear {
            if name.isEmpty { name = AppStore.seasonName(for: Calendar.current.date(byAdding: .year, value: 1, to: store.season.startedOn) ?? Date()) }
        }
    }
}
