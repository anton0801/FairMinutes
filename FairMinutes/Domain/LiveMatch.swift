import Foundation

enum MatchPhase: String, Codable {
    /// Set up, lineup planned, clock not started.
    case ready
    case running
    case paused
    /// Between two periods.
    case interval
    case finished
}

/// One continuous spell on the field in one place. Times are seconds into the period.
struct Stint: Codable, Equatable {
    var playerID: UUID
    var slot: Int
    var line: PitchLine
    var period: Int
    var from: Double
    var to: Double?
}

/// What the planner needs from outside the match: the squad and what the season has banked.
struct PlanningContext {
    var squad: [Player]
    var seasonSeconds: [UUID: Double]
    var seasonLineSeconds: [UUID: [PitchLine: Double]]
    var squadAverage: Double
    var settings: TeamSettings
}

/// The match in progress. The clock is never a counter: the running period stores the
/// moment it (re)started and the seconds banked before that, so the reading is always
/// recomputed from the device clock — a locked screen or a killed app loses nothing.
struct LiveMatch: Codable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var opponent: String
    var format: MatchFormat
    var attendance: [UUID: Attendance]
    var arrivals: [UUID: MatchInstant] = [:]
    var departures: [UUID: Departure] = [:]
    var phase: MatchPhase = .ready
    var period: Int = 0
    var elapsedBase: Double = 0
    var runStartedAt: Date?
    var periodDurations: [Double] = []
    var lineup: [Int: UUID] = [:]
    var stints: [Stint] = []
    var plan = SubPlan()
    var consumedUpTo: MatchInstant?
    var alerted: Set<String> = []
    /// The coach arranged the next kick-off lineup by hand; replans keep it.
    var manualLineup = false

    var periodCount: Int { format.periods.count }
    var isUnderway: Bool { phase == .running || phase == .paused }
    var periodName: String { format.periods.name(of: min(period, periodCount - 1)) }
    var isLastPeriod: Bool { period >= periodCount - 1 }

    // MARK: Clock

    func periodElapsed(at now: Date) -> Double {
        switch phase {
        case .running: return elapsedBase + max(0, now.timeIntervalSince(runStartedAt ?? now))
        case .paused: return elapsedBase
        default: return 0
        }
    }

    func instant(at now: Date) -> MatchInstant {
        switch phase {
        case .running, .paused: return MatchInstant(period: period, offset: periodElapsed(at: now))
        case .ready, .interval: return MatchInstant(period: period, offset: 0)
        case .finished: return MatchInstant(period: periodCount, offset: 0)
        }
    }

    /// The clock a coach reads: 20:00 at the start of the 2nd half of a 2 × 20 match.
    func nominalClock(at now: Date) -> Double {
        instant(at: now).nominalClock(periodSeconds: format.periodSeconds)
    }

    func overtime(at now: Date) -> Double {
        max(0, periodElapsed(at: now) - format.periodSeconds)
    }

    func instant(forMinute minute: Int) -> MatchInstant {
        let seconds = Double(max(0, minute) * 60)
        let length = format.periodSeconds
        let index = min(periodCount - 1, Int(seconds / max(1, length)))
        return MatchInstant(period: index, offset: seconds - Double(index) * length)
    }

    // MARK: Who is where

    func played(_ id: UUID, at now: Date) -> Double {
        let current = periodElapsed(at: now)
        return stints.reduce(0) { sum, stint in
            stint.playerID == id ? sum + max(0, (stint.to ?? current) - stint.from) : sum
        }
    }

    func lineSeconds(_ id: UUID, at now: Date) -> [PitchLine: Double] {
        let current = periodElapsed(at: now)
        var result: [PitchLine: Double] = [:]
        for stint in stints where stint.playerID == id {
            result[stint.line, default: 0] += max(0, (stint.to ?? current) - stint.from)
        }
        return result
    }

    func keptGoalPeriods(_ id: UUID) -> Set<Int> {
        Set(stints.filter { $0.playerID == id && $0.line == .goalkeeper }.map(\.period))
    }

    func slot(of id: UUID) -> Int? { lineup.first(where: { $0.value == id })?.key }
    func isOnField(_ id: UUID) -> Bool { slot(of: id) != nil }
    func isAttending(_ id: UUID) -> Bool { attendance[id]?.isComing == true }

    func hasArrived(_ id: UUID) -> Bool {
        switch attendance[id] {
        case .present: return true
        case .late: return arrivals[id] != nil
        default: return false
        }
    }

    func isAvailable(_ id: UUID) -> Bool { hasArrived(id) && departures[id] == nil }
    func isAwaited(_ id: UUID) -> Bool { isAttending(id) && !hasArrived(id) }

    func expectedMinute(_ id: UUID) -> Int? {
        if case .late(let minute) = attendance[id] { return minute }
        return nil
    }

    private func availableFrom(_ id: UUID, now: MatchInstant) -> MatchInstant? {
        guard case .late(let minute) = attendance[id], arrivals[id] == nil else { return nil }
        // Overdue children are assumed to be able to go on at the next window.
        return max(instant(forMinute: minute), MatchInstant(period: now.period, offset: now.offset + 1))
    }

    /// The next change inside the current period, if any is left.
    var nextWindowThisPeriod: PlanWindow? {
        guard isUnderway else { return nil }
        return plan.windows.first { $0.instant.period == period && !$0.isPeriodStart }
    }

    func secondsUntil(_ window: PlanWindow, at now: Date) -> Double {
        window.instant.offset - periodElapsed(at: now)
    }

    // MARK: Planning

    mutating func replan(_ context: PlanningContext, now: Date, fixed: Bool) {
        let at = instant(at: now)
        let attending = context.squad.filter { isAttending($0.id) }
        let attendingIDs = Set(attending.map(\.id))
        let players = attending.map { player in
            PlanPlayer(
                id: player.id,
                name: player.firstName,
                canKeepGoal: player.canPlayGoalkeeper,
                preferred: player.preferredLines,
                seasonSeconds: context.seasonSeconds[player.id] ?? 0,
                seasonLineSeconds: context.seasonLineSeconds[player.id] ?? [:],
                played: played(player.id, at: now),
                lineSecondsThisMatch: lineSeconds(player.id, at: now),
                keptGoalPeriods: keptGoalPeriods(player.id),
                availableFrom: availableFrom(player.id, now: at),
                departed: departures[player.id] != nil
            )
        }
        let request = PlanRequest(
            format: format,
            players: players,
            now: at,
            currentLineup: lineup.filter { attendingIDs.contains($0.value) },
            lineupIsFixed: fixed,
            consumedUpTo: consumedUpTo,
            seasonAdjustmentLimit: context.settings.seasonAdjustmentLimit,
            positionRotation: context.settings.positionRotation,
            squadSeasonAverage: context.squadAverage
        )
        plan = FairTimeEngine.plan(request)
        switch phase {
        case .running, .paused: apply(plan.startLineup, at: at)
        case .ready, .interval: lineup = plan.startLineup
        case .finished: break
        }
    }

    private mutating func apply(_ next: [Int: UUID], at instant: MatchInstant) {
        guard isUnderway else {
            lineup = next
            return
        }
        for (slot, id) in lineup where next[slot] != id {
            closeStint(of: id, at: instant.offset)
        }
        let formation = format.formation
        for (slot, id) in next where lineup[slot] != id {
            stints.append(Stint(playerID: id, slot: slot, line: formation.line(of: slot), period: period, from: instant.offset, to: nil))
        }
        lineup = next
    }

    private mutating func closeStint(of id: UUID, at offset: Double) {
        if let index = stints.lastIndex(where: { $0.playerID == id && $0.to == nil }) {
            stints[index].to = max(stints[index].from, offset)
        }
    }

    private var keepsLineup: Bool { isUnderway || manualLineup }

    // MARK: Actions

    mutating func start(_ context: PlanningContext, now: Date) {
        guard phase == .ready || phase == .interval else { return }
        phase = .running
        runStartedAt = now
        elapsedBase = 0
        let formation = format.formation
        for (slot, id) in lineup {
            stints.append(Stint(playerID: id, slot: slot, line: formation.line(of: slot), period: period, from: 0, to: nil))
        }
        consumedUpTo = MatchInstant(period: period, offset: 0)
        manualLineup = false
        replan(context, now: now, fixed: true)
    }

    mutating func pause(now: Date) {
        guard phase == .running else { return }
        elapsedBase = periodElapsed(at: now)
        runStartedAt = nil
        phase = .paused
    }

    mutating func resume(now: Date) {
        guard phase == .paused else { return }
        runStartedAt = now
        phase = .running
    }

    mutating func endPeriod(_ context: PlanningContext, now: Date) {
        guard isUnderway else { return }
        let elapsed = periodElapsed(at: now)
        for index in stints.indices where stints[index].to == nil {
            stints[index].to = max(stints[index].from, elapsed)
        }
        periodDurations.append(elapsed)
        runStartedAt = nil
        elapsedBase = 0
        if isLastPeriod {
            phase = .finished
            settleTargets(context)
        } else {
            period += 1
            phase = .interval
            consumedUpTo = nil
            manualLineup = false
            replan(context, now: now, fixed: false)
        }
    }

    mutating func confirm(_ window: PlanWindow, _ context: PlanningContext, now: Date) {
        guard isUnderway else { return }
        let at = instant(at: now)
        apply(window.lineup.filter { isAvailable($0.value) }, at: at)
        consumedUpTo = max(window.instant, at)
        replan(context, now: now, fixed: true)
    }

    /// Moves a child to a slot (swapping with whoever is there) or, with `slot == nil`,
    /// to the bench. A hole left on the field is filled by the planner at once.
    mutating func move(_ id: UUID, to slot: Int?, _ context: PlanningContext, now: Date) {
        guard isAvailable(id) else { return }
        var next = lineup
        let from = self.slot(of: id)
        if let slot {
            let occupant = next[slot]
            next[slot] = id
            if let from { next[from] = occupant }
        } else if let from {
            next[from] = nil
        } else {
            return
        }
        if next == lineup { return }
        if isUnderway {
            apply(next, at: instant(at: now))
        } else {
            lineup = next
            manualLineup = true
        }
        replan(context, now: now, fixed: true)
    }

    mutating func depart(_ id: UUID, reason: DepartureReason, _ context: PlanningContext, now: Date) {
        guard isAttending(id) else { return }
        if phase == .ready {
            // Before kick-off, going home is simply not being here today.
            setAttendance(id, .absent, context, now: now)
            return
        }
        if !hasArrived(id) {
            // A child who never turned up is simply not here today.
            attendance[id] = .absent
            replan(context, now: now, fixed: keepsLineup)
            return
        }
        departures[id] = Departure(at: instant(at: now), reason: reason)
        var next = lineup
        if let slot = slot(of: id) { next[slot] = nil }
        if isUnderway { apply(next, at: instant(at: now)) } else { lineup = next }
        replan(context, now: now, fixed: true)
    }

    mutating func returnToPlay(_ id: UUID, _ context: PlanningContext, now: Date) {
        guard departures[id] != nil else { return }
        departures[id] = nil
        replan(context, now: now, fixed: keepsLineup)
    }

    mutating func arrive(_ id: UUID, _ context: PlanningContext, now: Date) {
        if phase == .ready {
            // Turning up before kick-off is just being here.
            setAttendance(id, .present, context, now: now)
            return
        }
        let at = instant(at: now)
        if !isAttending(id) {
            attendance[id] = .late(expectedMinute: Int(at.nominalClock(periodSeconds: format.periodSeconds) / 60))
        }
        if case .late = attendance[id] { arrivals[id] = at }
        replan(context, now: now, fixed: keepsLineup)
    }

    mutating func setAttendance(_ id: UUID, _ value: Attendance, _ context: PlanningContext, now: Date) {
        attendance[id] = value
        if value == .absent {
            departures[id] = nil
            arrivals[id] = nil
            if let slot = slot(of: id), !isUnderway { lineup[slot] = nil }
        }
        if value == .present { arrivals[id] = nil }
        replan(context, now: now, fixed: keepsLineup)
    }

    // MARK: Record

    /// Converts a match instant into seconds of real playing time from kick-off.
    private func actualSeconds(_ instant: MatchInstant) -> Double {
        let before = periodDurations.prefix(max(0, min(instant.period, periodDurations.count))).reduce(0, +)
        guard instant.period < periodDurations.count else { return before }
        return before + min(instant.offset, periodDurations[instant.period])
    }

    /// Seconds a child could have been on the field: from arrival to departure or the whistle.
    func availableSeconds(_ id: UUID) -> Double {
        guard hasArrived(id) else { return 0 }
        let total = periodDurations.reduce(0, +)
        let from = arrivals[id].map(actualSeconds) ?? 0
        let to = departures[id].map { actualSeconds($0.at) } ?? total
        return max(0, to - from)
    }

    /// Once the whistle has gone, each target becomes the child's fair share of the minutes
    /// that were really played — the same formula and season adjustment, applied to the
    /// match as it happened. A child can then be over or under it, which is the point.
    mutating func settleTargets(_ context: PlanningContext) {
        let ids = context.squad.map(\.id).filter(hasArrived)
        let total = ids.reduce(0) { $0 + played($1, at: Date()) }
        var low: [UUID: Double] = [:]
        var high: [UUID: Double] = [:]
        var weights: [UUID: Double] = [:]
        let average = context.squadAverage
        let limit = max(0, context.settings.seasonAdjustmentLimit)
        for id in ids {
            high[id] = availableSeconds(id)
            // A keeper kept in goal all match by the format's rule is not "over" for it.
            low[id] = format.goalkeeperRotates ? 0 : min(high[id] ?? 0, lineSeconds(id, at: Date())[.goalkeeper] ?? 0)
            var boost = 0.0
            if average > 0 && limit > 0 {
                boost = min(limit, max(0, (average - (context.seasonSeconds[id] ?? 0)) / average))
            }
            weights[id] = 1 + boost
        }
        plan.targets = FairTimeEngine.waterFill(ids: ids, weights: weights, low: low, high: high, total: total)
        plan.expected = Dictionary(uniqueKeysWithValues: ids.map { ($0, played($0, at: Date())) })
        plan.windows = []
        plan.opening = nil
    }

    func record(squad: [Player]) -> MatchRecord {
        let entries = squad.map { player -> PlayerMatchEntry in
            let attended = hasArrived(player.id)
            return PlayerMatchEntry(
                playerID: player.id,
                firstName: player.firstName,
                shirtNumber: player.shirtNumber,
                attended: attended,
                arrivedAt: arrivals[player.id],
                departure: departures[player.id],
                playedSeconds: attended ? played(player.id, at: Date()) : 0,
                targetSeconds: attended ? (plan.targets[player.id] ?? 0) : 0,
                availableSeconds: availableSeconds(player.id),
                lineSeconds: attended ? lineSeconds(player.id, at: Date()) : [:]
            )
        }
        return MatchRecord(id: id, date: date, opponent: opponent, format: format, periodDurations: periodDurations, entries: entries)
    }
}
