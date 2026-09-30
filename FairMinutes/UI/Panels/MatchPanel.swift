import SwiftUI

/// The Match segment's own panel. Collapsed, it is the next change; pulled up, the plan.
struct MatchPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    @State private var confirmCancel = false
    @State private var confirmFinish = false

    var body: some View {
        if store.loadState == .loading {
            ListStateView(phase: .loading, emptyTitle: "", emptyMessage: "") { EmptyView() }
        } else if let match = store.data.liveMatch {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                live(match, now: context.date)
            }
        } else {
            idle
        }
    }

    // MARK: No match

    private var idle: some View {
        VStack(spacing: 0) {
            SummaryStrip(eyebrow: "Next match", headline: store.data.squad.isEmpty ? "no players yet" : "no match set up") {
                PrimaryButton(title: store.data.squad.isEmpty ? "add players" : "set up", height: 50) { openSetup() }
                    .frame(width: 150)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ListStateView(
                        phase: store.data.squad.isEmpty ? .empty : .ready,
                        emptyTitle: "No players yet",
                        emptyMessage: "Add the children in Squad — first name and shirt number are enough.",
                        emptyAction: ("add players", openSetup)
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            SectionHeading("next match")
                            Text("Tap the shirts of the children who came. The substitution plan is built straight away, with everyone close to the same minutes.")
                                .font(Typeface.body)
                                .foregroundColor(Palette.anchor)
                                .fixedSize(horizontal: false, vertical: true)
                            PrimaryButton(title: "set up next match", systemImage: "person.3.fill") { openSetup() }
                        }
                    }
                    if let last = store.season.matches.last {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeading("last match")
                            LinkRow(title: last.opponent.isEmpty ? "Match" : "vs \(last.opponent)", value: last.date.formatted(date: .abbreviated, time: .omitted)) {
                                screen.push(.summary(last.id))
                            }
                        }
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
        }
    }

    private func openSetup() {
        if store.data.squad.isEmpty {
            screen.select(.squad)
            screen.push(.editPlayer(nil), in: .squad)
        } else {
            screen.push(.matchSetup)
        }
    }

    // MARK: Live

    @ViewBuilder
    private func live(_ match: LiveMatch, now: Date) -> some View {
        VStack(spacing: 0) {
            strip(match, now: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MatchControls(match: match)
                    if let opening = match.plan.opening, match.phase == .interval, opening.hasChanges {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionHeading("changes at the break")
                            WindowRow(window: opening, match: match, store: store, isNext: false, now: now)
                        }
                    }
                    if !match.plan.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(match.plan.notes, id: \.self) { note in
                                NoteLine(text: note, tint: note.contains("extra") ? Palette.yellow : Palette.blue)
                            }
                        }
                    }
                    planSection(match, now: now)
                    minutesSection(match, now: now)
                    notHereSection(match)
                    if match.phase == .ready {
                        HStack(spacing: 10) {
                            SecondaryButton(title: "who came", systemImage: "person.crop.circle.badge.checkmark", height: 48) {
                                screen.push(.matchSetup)
                            }
                            SecondaryButton(title: "cancel match", tint: Palette.red, height: 48) { confirmCancel = true }
                        }
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
        }
        .confirmationDialog("Cancel this match?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Cancel Match", role: .destructive) { store.cancelMatch() }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("The plan is discarded. Nothing is added to the season.")
        }
        .confirmationDialog("End the match?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("End Match and Record Minutes") { store.endPeriod() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Every child's minutes go into the season. This cannot be undone.")
        }
    }

    @ViewBuilder
    private func strip(_ match: LiveMatch, now: Date) -> some View {
        let over = match.phase == .running && match.periodElapsed(at: now) >= match.format.periodSeconds
        if match.phase == .ready {
            let bench = match.attendance.keys.filter { match.isAvailable($0) && !match.isOnField($0) }.count
            SummaryStrip(eyebrow: "Kick-off lineup ready", headline: "\(match.lineup.count) on · \(bench) on the bench") {
                PrimaryButton(title: "start", systemImage: "play.fill", height: 50) {
                    store.startPeriod()
                    screen.detent = .collapsed
                }
                .frame(width: 124)
            }
        } else if match.phase == .interval {
            let changes = (match.plan.opening?.comingOn.count ?? 0)
            SummaryStrip(eyebrow: match.format.periods == .halves ? "Half-time" : "Break", headline: changes == 0 ? "same lineup" : "\(changes) \(changes == 1 ? "change" : "changes") to make") {
                PrimaryButton(title: "start", systemImage: "play.fill", height: 50) {
                    store.startPeriod()
                    screen.detent = .collapsed
                }
                .frame(width: 124)
            }
        } else if match.phase == .paused {
            SummaryStrip(eyebrow: "Paused at \(Minutes.clock(match.nominalClock(at: now)))", headline: "clock stopped") {
                PrimaryButton(title: "resume", systemImage: "play.fill", height: 50, action: store.resume)
                    .frame(width: 136)
            }
        } else if over {
            SummaryStrip(eyebrow: "Time is up · \(match.periodName)", headline: match.isLastPeriod ? "full time?" : "end the period?", tint: Palette.red) {
                PrimaryButton(title: "end", systemImage: "stop.fill", height: 50) {
                    if match.isLastPeriod { confirmFinish = true } else { store.endPeriod() }
                }
                .frame(width: 110)
            }
        } else if let next = match.nextWindowThisPeriod {
            let until = match.secondsUntil(next, at: now)
            let due = until <= 60
            SummaryStrip(
                eyebrow: until <= 0 ? "Change now · \(clock(next, match))" : "Next change \(clock(next, match)) · in \(Minutes.countdown(until))",
                headline: headline(for: next),
                tint: due ? Palette.red : Palette.anchor
            ) {
                if due {
                    PrimaryButton(title: "confirm", systemImage: "checkmark", height: 50) { store.confirm(next) }
                        .frame(width: 136)
                } else {
                    SecondaryButton(title: "pause", systemImage: "pause.fill", height: 50, action: store.pause)
                        .frame(width: 124)
                }
            }
        } else {
            SummaryStrip(eyebrow: "No more changes in the \(match.periodName.lowercased())", headline: match.isLastPeriod ? "play it out" : "next change at the break") {
                SecondaryButton(title: "pause", systemImage: "pause.fill", height: 50, action: store.pause)
                    .frame(width: 124)
            }
        }
    }

    private func clock(_ window: PlanWindow, _ match: LiveMatch) -> String {
        Minutes.clock(window.instant.nominalClock(periodSeconds: match.format.periodSeconds))
    }

    private func headline(for window: PlanWindow) -> String {
        let off = window.goingOff.map(store.name)
        let on = window.comingOn.map(store.name)
        if off.isEmpty && on.isEmpty { return "positions change" }
        if off.count + on.count <= 3 {
            let offText = off.isEmpty ? "" : "\(FairTimeEngine.listed(off)) off"
            let onText = on.isEmpty ? "" : "\(FairTimeEngine.listed(on)) on"
            return [offText, onText].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        return "\(off.count) off · \(on.count) on"
    }

    @ViewBuilder
    private func planSection(_ match: LiveMatch, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("substitution plan", detail: "\(match.format.substitutionRule.title)")
            let upcoming = match.plan.windows
            ListStateView(
                phase: upcoming.isEmpty ? .empty : .ready,
                emptyTitle: "No more changes",
                emptyMessage: match.attendance.keys.contains(where: match.isAvailable)
                    ? "Everyone stays where they are until the end."
                    : "No one is available. Mark who came to build a plan."
            ) {
                VStack(spacing: 0) {
                    ForEach(upcoming) { window in
                        WindowRow(window: window, match: match, store: store, isNext: match.isUnderway && window.id == match.nextWindowThisPeriod?.id, now: now)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func minutesSection(_ match: LiveMatch, now: Date) -> some View {
        let players = store.squadByName.filter { match.isAttending($0.id) }
        VStack(alignment: .leading, spacing: 6) {
            SectionHeading("minutes today", detail: "played / target")
            if match.plan.fairShare > 0 {
                Text("Fair share: \(match.format.playersOnField) on the field × \(match.format.matchMinutes) min ÷ \(players.count) here = \(Minutes.whole(match.plan.fairShare)) min each.")
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(players) { player in
                Button {
                    screen.push(.player(player.id), detent: .medium)
                } label: {
                    MinutesRow(player: player, match: match, now: now)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func notHereSection(_ match: LiveMatch) -> some View {
        let away = store.squadByName.filter { !match.isAttending($0.id) }
        if !away.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading("not here today")
                ForEach(away) { player in
                    HStack {
                        MiniPlayer(name: player.firstName, number: player.shirtNumber, tone: .away)
                        Spacer()
                        Button("arrived") { store.arrive(player.id) }
                            .font(Typeface.smallButton)
                            .foregroundColor(Palette.blue)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
    }
}
