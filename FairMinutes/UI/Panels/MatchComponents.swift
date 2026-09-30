import SwiftUI

/// A small shirt with a name beside it — how a child appears in lists and plans.
struct MiniPlayer: View {
    let name: String
    let number: Int
    var tone: JerseyTone = .plain
    var detail: String?

    var body: some View {
        HStack(spacing: 8) {
            JerseyView(number: number, tone: tone, width: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(Typeface.bodyBold)
                    .foregroundColor(Palette.anchor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(Typeface.caption)
                        .foregroundColor(Palette.muted)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One window of the plan: when, who goes off, who goes on, who changes place.
struct WindowRow: View {
    let window: PlanWindow
    let match: LiveMatch
    let store: AppStore
    let isNext: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Minutes.clock(window.instant.nominalClock(periodSeconds: match.format.periodSeconds)))
                    .font(.system(size: Typeface.scaled(22, .title3), weight: .heavy).monospacedDigit())
                    .foregroundColor(isNext ? Palette.red : Palette.anchor)
                Text(caption)
                    .font(Typeface.label)
                    .foregroundColor(isNext ? Palette.red : Palette.muted)
                Spacer(minLength: 0)
            }
            if !window.goingOff.isEmpty {
                group(label: "off", ids: window.goingOff, tone: isNext ? .nextChange : .onField)
            }
            if !window.comingOn.isEmpty {
                group(label: "on", ids: window.comingOn, tone: isNext ? .nextChange : .bench)
            }
            let moves = window.moved.filter { !window.comingOn.contains($0) }
            if !moves.isEmpty {
                Text(moves.map { id -> String in
                    let slot = window.lineup.first { $0.value == id }?.key ?? 0
                    return "\(store.name(id)) moves to \(match.format.formation.line(of: slot).title.lowercased())"
                }.joined(separator: " · "))
                .font(Typeface.caption)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            if !window.hasChanges {
                Text("No changes.")
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Palette.marking.frame(height: Metric.line) }
        .accessibilityElement(children: .combine)
    }

    private var caption: String {
        if window.isPeriodStart {
            return "\(match.format.periods.name(of: window.instant.period)) starts"
        }
        guard isNext, match.isUnderway else { return match.format.periods.shortName(of: window.instant.period) }
        let until = match.secondsUntil(window, at: now)
        return until <= 0 ? "due now" : "in \(Minutes.countdown(until))"
    }

    private func group(label: String, ids: [UUID], tone: JerseyTone) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 13, weight: .heavy).italic())
                .foregroundColor(Palette.muted)
                .frame(width: 26, alignment: .leading)
                .padding(.top, 8)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    MiniPlayer(name: store.name(id), number: store.player(id)?.shirtNumber ?? 0, tone: tone)
                }
            }
        }
    }
}

/// Minutes so far against target, with what the plan expects by full time.
struct MinutesRow: View {
    let player: Player
    let match: LiveMatch
    let now: Date

    var body: some View {
        let played = match.played(player.id, at: now)
        let target = match.plan.targets[player.id] ?? 0
        let expected = match.plan.expected[player.id] ?? played
        HStack(spacing: 10) {
            JerseyView(number: player.shirtNumber, tone: tone, width: 32)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(player.firstName)
                        .font(Typeface.bodyBold)
                        .foregroundColor(Palette.anchor)
                        .lineLimit(1)
                    Text(status)
                        .font(Typeface.caption)
                        .foregroundColor(Palette.muted)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(Minutes.whole(played)) / \(Minutes.whole(target))")
                        .font(.system(size: Typeface.scaled(16), weight: .heavy).monospacedDigit())
                        .foregroundColor(Palette.anchor)
                }
                HStack(spacing: 8) {
                    GeometryReader { proxy in
                        MinutesBar(progress: target > 0 ? played / target : 0, width: proxy.size.width)
                    }
                    .frame(height: 4)
                    Text("plan \(Minutes.whole(expected))")
                        .font(Typeface.caption)
                        .foregroundColor(expected + 60 < target ? Palette.red : Palette.muted)
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(player.firstName), \(status). \(Minutes.whole(played)) of \(Minutes.whole(target)) minutes, plan \(Minutes.whole(expected)).")
    }

    private var tone: JerseyTone {
        if match.departures[player.id] != nil { return .away }
        if match.isAwaited(player.id) { return .awaited }
        return match.isOnField(player.id) ? .onField : .bench
    }

    private var status: String {
        if let departure = match.departures[player.id] {
            return "\(departure.reason == .injury ? "injured" : "left") \(Minutes.clockMinute(departure.at, format: match.format))"
        }
        if match.isAwaited(player.id) {
            return match.expectedMinute(player.id).map { "due \($0)′" } ?? "not here yet"
        }
        if let slot = match.slot(of: player.id) {
            return match.format.formation.line(of: slot).title.lowercased()
        }
        return "bench"
    }
}

/// Start/Pause, Sub Now, End Period, Injury, Left Early — the whole live control set.
struct MatchControls: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let match: LiveMatch
    @State private var confirmEnd = false

    var body: some View {
        VStack(spacing: 10) {
            switch match.phase {
            case .ready, .interval:
                PrimaryButton(title: "start \(match.periodName)", systemImage: "play.fill") {
                    store.startPeriod()
                    screen.detent = .collapsed
                }
            case .running:
                SecondaryButton(title: "pause", systemImage: "pause.fill", action: store.pause)
            case .paused:
                PrimaryButton(title: "resume", systemImage: "play.fill", action: store.resume)
            case .finished:
                EmptyView()
            }
            HStack(spacing: 10) {
                SecondaryButton(title: "sub now", systemImage: "arrow.left.arrow.right", height: 48, isEnabled: match.nextWindowThisPeriod != nil) {
                    store.subNow()
                    if store.data.settings.hapticAlerts { Haptics.tap() }
                }
                SecondaryButton(title: endTitle, systemImage: "stop.fill", height: 48, isEnabled: match.isUnderway) {
                    if match.isLastPeriod { confirmEnd = true } else { store.endPeriod() }
                }
            }
            HStack(spacing: 10) {
                SecondaryButton(title: "injury", systemImage: "cross.case.fill", tint: Palette.red, height: 48, isEnabled: hasAvailable) {
                    screen.push(.departure(.injury), detent: .medium)
                }
                SecondaryButton(title: "left early", systemImage: "figure.walk", height: 48, isEnabled: hasAvailable) {
                    screen.push(.departure(.leftEarly), detent: .medium)
                }
            }
        }
        .confirmationDialog("End the match?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End Match and Record Minutes") { store.endPeriod() }
            Button("Keep Playing", role: .cancel) {}
        } message: {
            Text("Every child's minutes go into the season. This cannot be undone.")
        }
    }

    private var hasAvailable: Bool {
        match.attendance.keys.contains { match.isAvailable($0) }
    }

    private var endTitle: String {
        if match.isLastPeriod { return "end match" }
        return match.format.periods == .halves ? "end half" : "end quarter"
    }
}
