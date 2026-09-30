import SwiftUI

// MARK: - Attendance

/// Tap a shirt: here → not here → arriving late → here.
struct AttendanceGrid: View {
    let players: [Player]
    @Binding var attendance: [UUID: Attendance]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 14) {
            ForEach(players) { player in
                let state = attendance[player.id] ?? .present
                Button {
                    Haptics.tap()
                    switch state {
                    case .present: attendance[player.id] = .absent
                    case .absent: attendance[player.id] = .late(expectedMinute: 10)
                    case .late: attendance[player.id] = .present
                    }
                } label: {
                    VStack(spacing: 4) {
                        PlayerToken(
                            player: player,
                            tone: tone(state),
                            progress: nil,
                            width: 56,
                            badge: { if case .late(let minute) = state { return "\(minute)′" } else { return nil } }()
                        )
                        Text(caption(state))
                            .font(Typeface.caption)
                            .foregroundColor(state == .absent ? Palette.muted : Palette.anchor)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(player.firstName), number \(player.shirtNumber)")
                .accessibilityValue(caption(state))
                .accessibilityHint("Double-tap to change.")
            }
        }
    }

    private func tone(_ state: Attendance) -> JerseyTone {
        switch state {
        case .present: return .onField
        case .late: return .awaited
        case .absent: return .away
        }
    }

    private func caption(_ state: Attendance) -> String {
        switch state {
        case .present: return "here"
        case .late: return "late"
        case .absent: return "not here"
        }
    }
}

/// Steppers for the expected arrival minute of every child marked late.
struct LateArrivals: View {
    let players: [Player]
    @Binding var attendance: [UUID: Attendance]
    let matchMinutes: Int

    var body: some View {
        let late = players.filter { if case .late = attendance[$0.id] { return true } else { return false } }
        if !late.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Expected arrival")
                    .font(Typeface.label)
                    .foregroundColor(Palette.muted)
                ForEach(late) { player in
                    CountStepper(
                        label: player.firstName,
                        value: Binding(
                            get: { if case .late(let minute) = attendance[player.id] { return minute } else { return 10 } },
                            set: { attendance[player.id] = .late(expectedMinute: $0) }
                        ),
                        range: 1...max(1, matchMinutes - 1),
                        format: { "\($0)′" }
                    )
                }
            }
        }
    }
}

struct MatchSetupPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    @State private var date = Date()
    @State private var opponent = ""
    @State private var attendance: [UUID: Attendance] = [:]
    @State private var prepared = false

    var body: some View {
        let format = store.data.format
        let players = store.squadByName
        let here = players.filter { attendance[$0.id] != .absent }.count
        PanelScaffold(
            title: "next match",
            subtitle: "\(format.playersOnField)-a-side · \(format.periods.count) × \(format.periodMinutes) min · \(format.substitutionRule.title)",
            onBack: screen.pop
        ) {
            LabeledField(label: "Date and kick-off") {
                DatePicker("Date and kick-off", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(Palette.blue)
            }
            LabeledField(label: "Opponent") {
                OutlinedTextField(placeholder: "e.g. Riverside", text: $opponent)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeading("who came today", detail: counts(players))
                Text("Tap a shirt: here → not here → late.")
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                ListStateView(
                    phase: players.isEmpty ? .empty : .ready,
                    emptyTitle: "No players yet",
                    emptyMessage: "Add players in Squad first."
                ) {
                    AttendanceGrid(players: players, attendance: $attendance)
                }
                LateArrivals(players: players, attendance: $attendance, matchMinutes: format.matchMinutes)
            }
            if here > 0 && here < format.playersOnField {
                NoteLine(text: "Only \(here) for \(format.playersOnField)-a-side. Everyone plays the whole match and the empty places stay open.", tint: Palette.yellow)
            }
            PrimaryButton(title: "build the plan", systemImage: "list.number", isEnabled: here > 0) {
                store.setUpMatch(date: date, opponent: opponent, attendance: attendance)
                screen.popToRoot(.match, detent: .medium)
            }
        }
        .onAppear(perform: prepare)
    }

    private func counts(_ players: [Player]) -> String {
        let here = players.filter { attendance[$0.id] == .present }.count
        let late = players.filter { if case .late = attendance[$0.id] { return true } else { return false } }.count
        return late > 0 ? "\(here) here · \(late) late" : "\(here) of \(players.count)"
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let match = store.data.liveMatch, match.phase == .ready {
            date = match.date
            opponent = match.opponent
            attendance = match.attendance
        } else {
            attendance = Dictionary(uniqueKeysWithValues: store.data.squad.map { ($0.id, Attendance.present) })
        }
        for player in store.data.squad where attendance[player.id] == nil {
            attendance[player.id] = .absent
        }
    }
}

// MARK: - One child during the match

struct PlayerMatchPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let playerID: UUID
    @State private var pending: DepartureReason?

    var body: some View {
        if let player = store.player(playerID), let match = store.data.liveMatch {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(player, match, now: context.date)
            }
        } else {
            PanelScaffold(title: "player", onBack: screen.pop) {
                ListStateView(phase: .failed("This player is not part of a match right now."), emptyTitle: "", emptyMessage: "", retry: screen.pop) { EmptyView() }
            }
        }
    }

    private func content(_ player: Player, _ match: LiveMatch, now: Date) -> some View {
        let played = match.played(player.id, at: now)
        let target = match.plan.targets[player.id] ?? 0
        let expected = match.plan.expected[player.id] ?? played
        let lines = match.lineSeconds(player.id, at: now).filter { $0.value >= 30 }

        return PanelScaffold(title: player.firstName, keepsCase: true, subtitle: "No. \(player.shirtNumber) · \(status(player, match))", onBack: screen.pop) {
            JerseyView(number: player.shirtNumber, tone: tone(player, match), width: 72)
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 8) {
                    Text("\(Minutes.whole(played))")
                        .font(Typeface.minutes())
                        .foregroundColor(Palette.anchor)
                    Text("of \(Minutes.whole(target)) min target")
                        .font(Typeface.bodyBold)
                        .foregroundColor(Palette.muted)
                }
                GeometryReader { proxy in
                    MinutesBar(progress: target > 0 ? played / target : 0, width: proxy.size.width, height: 6)
                }
                .frame(height: 6)
                if match.phase != .finished && match.isAttending(player.id) {
                    Text("The plan takes \(player.firstName) to \(Minutes.text(expected)) by full time.")
                        .font(Typeface.body)
                        .foregroundColor(Palette.anchor)
                        .padding(.top, 4)
                }
            }
            .accessibilityElement(children: .combine)

            if let next = nextChange(player, match) {
                NoteLine(text: next, tint: Palette.red)
            }
            if !lines.isEmpty {
                Text("Today: " + PitchLine.allCases.compactMap { line in lines[line].map { "\(line.title) \(Minutes.short($0))" } }.joined(separator: " · "))
                    .font(Typeface.body)
                    .foregroundColor(Palette.anchor)
            }
            if !player.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes for coach")
                        .font(Typeface.label)
                        .foregroundColor(Palette.muted)
                    NoteLine(text: player.notes, tint: Palette.yellow)
                }
            }
            actions(player, match)
        }
        .confirmationDialog(
            pending.map { "\(player.firstName) \($0.pastTense)?" } ?? "",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            Button(pending == .injury ? "Off Injured" : "Left Early", role: .destructive) {
                if let reason = pending {
                    store.depart(player.id, reason: reason)
                    screen.popToRoot(.match, detent: .medium)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(player.firstName) comes out of the rest of the plan and the changes are rebuilt for everyone else.")
        }
    }

    @ViewBuilder
    private func actions(_ player: Player, _ match: LiveMatch) -> some View {
        VStack(spacing: 10) {
            if match.isAwaited(player.id) {
                PrimaryButton(title: "arrived now", systemImage: "hand.wave.fill") { store.arrive(player.id) }
                SecondaryButton(title: "not coming today", height: 48) {
                    store.setAttendance(player.id, .absent)
                    screen.pop()
                }
            } else if !match.isAttending(player.id) {
                PrimaryButton(title: "arrived now", systemImage: "hand.wave.fill") { store.arrive(player.id) }
            } else if match.departures[player.id] != nil {
                PrimaryButton(title: "available again", systemImage: "arrow.uturn.backward") { store.returnToPlay(player.id) }
            } else if match.phase != .finished {
                HStack(spacing: 10) {
                    SecondaryButton(title: "swap with…", systemImage: "arrow.left.arrow.right", height: 48) {
                        screen.push(.swap(player.id), detent: .medium)
                    }
                    if match.isOnField(player.id) {
                        SecondaryButton(title: "to the bench", systemImage: "arrow.down", height: 48) {
                            if let preview = store.previewMove(player.id, to: nil) {
                                screen.push(.move(preview), detent: .medium)
                            }
                        }
                    }
                }
                HStack(spacing: 10) {
                    SecondaryButton(title: "injury", systemImage: "cross.case.fill", tint: Palette.red, height: 48) { pending = .injury }
                    SecondaryButton(title: "left early", systemImage: "figure.walk", height: 48) { pending = .leftEarly }
                }
            }
        }
    }

    private func tone(_ player: Player, _ match: LiveMatch) -> JerseyTone {
        if match.departures[player.id] != nil || !match.isAttending(player.id) { return .away }
        if match.isAwaited(player.id) { return .awaited }
        return match.isOnField(player.id) ? .onField : .bench
    }

    private func status(_ player: Player, _ match: LiveMatch) -> String {
        if let departure = match.departures[player.id] {
            return "\(departure.reason.pastTense) at \(Minutes.clockMinute(departure.at, format: match.format))"
        }
        if !match.isAttending(player.id) { return "not here today" }
        if match.isAwaited(player.id) { return match.expectedMinute(player.id).map { "due at \($0)′" } ?? "not here yet" }
        if let slot = match.slot(of: player.id) { return "on the field · \(match.format.formation.line(of: slot).title.lowercased())" }
        return "on the bench"
    }

    private func nextChange(_ player: Player, _ match: LiveMatch) -> String? {
        guard match.isAvailable(player.id), match.phase != .finished else { return nil }
        for window in match.plan.windows {
            let clock = Minutes.clock(window.instant.nominalClock(periodSeconds: match.format.periodSeconds))
            if window.goingOff.contains(player.id) { return "Comes off at \(clock)." }
            if window.comingOn.contains(player.id) { return "Goes on at \(clock)." }
        }
        return match.isOnField(player.id) ? "Stays on until the end." : "No more time planned in this match."
    }
}

// MARK: - Injury / Left Early

struct DeparturePanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let reason: DepartureReason
    @State private var chosen: UUID?

    var body: some View {
        let match = store.data.liveMatch
        let players = store.squadByName.filter { match?.isAvailable($0.id) == true }
        let ordered = players.filter { match?.isOnField($0.id) == true } + players.filter { match?.isOnField($0.id) != true }
        PanelScaffold(title: reason == .injury ? "injury" : "left early", subtitle: "Who is coming off?", onBack: screen.pop) {
            Text("The plan is rebuilt for everyone else straight away.")
                .font(Typeface.body)
                .foregroundColor(Palette.anchor)
            ListStateView(phase: ordered.isEmpty ? .empty : .ready, emptyTitle: "No one to take off", emptyMessage: "Everyone here has already come off.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 14) {
                    ForEach(ordered) { player in
                        Button {
                            chosen = player.id
                        } label: {
                            PlayerToken(player: player, tone: match?.isOnField(player.id) == true ? .onField : .bench, progress: nil, width: 56)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(player.firstName), number \(player.shirtNumber)")
                    }
                }
            }
        }
        .confirmationDialog(
            chosen.map { "\(store.name($0)) \(reason.pastTense)?" } ?? "",
            isPresented: Binding(get: { chosen != nil }, set: { if !$0 { chosen = nil } }),
            titleVisibility: .visible
        ) {
            Button(reason == .injury ? "Off Injured" : "Left Early", role: .destructive) {
                if let id = chosen {
                    store.depart(id, reason: reason)
                    screen.popToRoot(.match, detent: .medium)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Manual swap

struct SwapPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let playerID: UUID

    var body: some View {
        let match = store.data.liveMatch
        let onField = match?.isOnField(playerID) == true
        let candidates = store.squadByName.filter { player in
            guard player.id != playerID, let match, match.isAvailable(player.id) else { return false }
            return onField || match.isOnField(player.id)
        }
        PanelScaffold(title: "swap \(store.name(playerID))", keepsCase: true, subtitle: onField ? "With someone on the bench or another place" : "With someone on the field", onBack: screen.pop) {
            ListStateView(phase: candidates.isEmpty ? .empty : .ready, emptyTitle: "No one to swap with", emptyMessage: "There is nobody available on the other side.") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 14) {
                    ForEach(candidates) { player in
                        Button {
                            choose(player.id, in: match)
                        } label: {
                            PlayerToken(player: player, tone: match?.isOnField(player.id) == true ? .onField : .bench, progress: nil, width: 56)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(player.firstName), number \(player.shirtNumber)")
                    }
                }
            }
        }
    }

    private func choose(_ other: UUID, in match: LiveMatch?) {
        guard let match else { return }
        let preview: MovePreview?
        if let mine = match.slot(of: playerID) {
            if let theirs = match.slot(of: other) {
                preview = store.previewMove(playerID, to: theirs)
            } else {
                preview = store.previewMove(other, to: mine)
            }
        } else if let theirs = match.slot(of: other) {
            preview = store.previewMove(playerID, to: theirs)
        } else {
            preview = nil
        }
        if let preview { screen.push(.move(preview), detent: .medium) }
    }
}

/// "This leaves Sam 6 minutes under target. Next window: 18:00."
struct MovePreviewPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let preview: MovePreview

    var body: some View {
        PanelScaffold(title: "manual change", subtitle: preview.title, onBack: screen.pop) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(preview.lines, id: \.self) { line in
                    NoteLine(text: line, tint: line.contains("under") ? Palette.red : (line.contains("over") ? Palette.yellow : Palette.blue))
                }
                if let next = preview.nextWindow {
                    Text(next)
                        .font(Typeface.bodyBold)
                        .foregroundColor(Palette.anchor)
                }
            }
            HStack(spacing: 10) {
                SecondaryButton(title: "keep the plan", action: screen.pop)
                PrimaryButton(title: "make the change") {
                    store.move(preview.playerID, to: preview.slot)
                    Haptics.tap()
                    screen.popToRoot(.match, detent: .collapsed)
                }
            }
        }
    }
}

// MARK: - Match summary

struct MatchSummaryPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let recordID: UUID
    @State private var confirmDelete = false

    var body: some View {
        if let record = store.record(recordID) {
            content(record)
        } else {
            PanelScaffold(title: "match", onBack: { screen.popToRoot(detent: .medium) }) {
                ListStateView(phase: .failed("This match is no longer in the season."), emptyTitle: "", emptyMessage: "", retry: { screen.popToRoot(detent: .medium) }) { EmptyView() }
            }
        }
    }

    private func content(_ record: MatchRecord) -> some View {
        let attendees = record.attendees
        let absent = record.entries.filter { !$0.attended }.map(\.firstName).sorted()
        let fullMatch = attendees.filter { $0.arrivedAt == nil && $0.departure == nil }.map { Minutes.whole($0.playedSeconds) }
        let versus = record.opponent.isEmpty ? "Match" : "vs \(record.opponent)"
        return PanelScaffold(
            title: record.id == store.justFinishedMatchID ? "full time" : versus,
            subtitle: "\(record.id == store.justFinishedMatchID ? versus + " · " : "")\(record.date.formatted(date: .abbreviated, time: .omitted)) · \(record.format.playersOnField)-a-side · \(Minutes.whole(record.totalSeconds)) min played",
            onBack: done
        ) {
            if let low = fullMatch.min(), let high = fullMatch.max() {
                NoteLine(text: low == high ? "Everyone played \(low) minutes." : "Everyone here for the whole match played between \(low) and \(high) minutes.")
            }
            VStack(alignment: .leading, spacing: 0) {
                SectionHeading("minutes", detail: "against target")
                ListStateView(phase: attendees.isEmpty ? .empty : .ready, emptyTitle: "Nobody played", emptyMessage: "No one was marked as here for this match.") {
                    ForEach(attendees) { entry in
                        SummaryRow(entry: entry, record: record, teamName: store.data.teamName)
                    }
                }
            }
            if !absent.isEmpty {
                Text("Not here: \(FairTimeEngine.listed(absent)).")
                    .font(Typeface.body)
                    .foregroundColor(Palette.muted)
            }
            Text("Minutes only. No goals, no ratings, no best players.")
                .font(Typeface.caption)
                .foregroundColor(Palette.muted)
            PrimaryButton(title: "done", action: done)
            SecondaryButton(title: "delete this match", tint: Palette.red, height: 48) { confirmDelete = true }
        }
        .confirmationDialog("Delete this match?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Match", role: .destructive) {
                store.deleteMatch(record.id)
                screen.popToRoot(detent: .medium)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its minutes are removed from the season totals.")
        }
    }

    private func done() {
        store.justFinishedMatchID = nil
        screen.popToRoot(detent: screen.segment == .match ? .medium : nil)
    }
}

private struct SummaryRow: View {
    let entry: PlayerMatchEntry
    let record: MatchRecord
    let teamName: String

    var body: some View {
        let deviation = entry.deviationSeconds
        HStack(alignment: .center, spacing: 10) {
            JerseyView(number: entry.shirtNumber, tone: deviation <= -60 ? .nextChange : .onField, width: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.firstName)
                        .font(Typeface.bodyBold)
                        .foregroundColor(Palette.anchor)
                    Text("\(Minutes.whole(entry.playedSeconds)) min")
                        .font(.system(size: Typeface.scaled(17), weight: .heavy).monospacedDigit())
                        .foregroundColor(Palette.anchor)
                    DeviationChip(seconds: deviation)
                }
                Text(detail)
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button {
                ShareSheet.present([ParentSummary.match(record, entry: entry, teamName: teamName)])
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Palette.blue)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Share \(entry.firstName)'s minutes with the family")
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Palette.marking.frame(height: Metric.line) }
    }

    private var detail: String {
        var parts = PitchLine.allCases.compactMap { line -> String? in
            guard let seconds = entry.lineSeconds[line], seconds >= 30 else { return nil }
            return "\(line.short) \(Minutes.whole(seconds))"
        }
        parts.insert("target \(Minutes.whole(entry.targetSeconds))", at: 0)
        if let arrived = entry.arrivedAt { parts.append("arrived \(Minutes.clockMinute(arrived, format: record.format))") }
        if let departure = entry.departure {
            parts.append("\(departure.reason == .injury ? "injured" : "left") \(Minutes.clockMinute(departure.at, format: record.format))")
        }
        return parts.joined(separator: " · ")
    }
}

struct DeviationChip: View {
    let seconds: Double

    var body: some View {
        let minutes = Minutes.whole(seconds)
        Text(Minutes.signed(seconds))
            .font(.system(size: 13, weight: .heavy).monospacedDigit())
            .foregroundColor(minutes < 0 ? .white : Palette.anchor)
            .padding(.horizontal, 7)
            .frame(minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(minutes < 0 ? Palette.red : Palette.ground))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(minutes < 0 ? Palette.red : (minutes > 0 ? Palette.blue : Palette.anchor), lineWidth: 2))
            .accessibilityLabel(minutes == 0 ? "on target" : (minutes > 0 ? "\(minutes) over target" : "\(-minutes) under target"))
    }
}
