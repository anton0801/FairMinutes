import Foundation

/// Everything the engine needs to know about one child for one planning pass.
struct PlanPlayer {
    let id: UUID
    let name: String
    let canKeepGoal: Bool
    let preferred: Set<PitchLine>
    /// Minutes (in seconds) this child has banked earlier in the season.
    let seasonSeconds: Double
    let seasonLineSeconds: [PitchLine: Double]
    /// Already on the clock in this match.
    let played: Double
    let lineSecondsThisMatch: [PitchLine: Double]
    let keptGoalPeriods: Set<Int>
    /// The first moment this child can go on. `nil` means already here.
    let availableFrom: MatchInstant?
    let departed: Bool
}

struct PlanRequest {
    var format: MatchFormat
    var players: [PlanPlayer]
    /// Where the match is now. Before kick-off and during a break this is (period, 0).
    var now: MatchInstant
    /// Who is on the field now (or who was on at the end of the last period).
    var currentLineup: [Int: UUID]
    /// When true the current lineup holds until the next window; only empty slots are filled.
    var lineupIsFixed: Bool
    /// Windows at or before this instant have already been used.
    var consumedUpTo: MatchInstant?
    var seasonAdjustmentLimit: Double
    var positionRotation: Bool
    /// Team average of banked season seconds. Zero before the first recorded match.
    var squadSeasonAverage: Double
}

struct PlanWindow: Codable, Equatable, Identifiable {
    var instant: MatchInstant
    var lineup: [Int: UUID]
    var comingOn: [UUID]
    var goingOff: [UUID]
    var moved: [UUID]

    var id: String { instant.key }
    var isPeriodStart: Bool { instant.offset == 0 }
    var hasChanges: Bool { !comingOn.isEmpty || !goingOff.isEmpty || !moved.isEmpty }
}

struct SubPlan: Codable, Equatable {
    /// The lineup from `now` until the first window.
    var startLineup: [Int: UUID] = [:]
    /// The change that happens at `now` itself, when `now` is a window (kick-off, a break).
    var opening: PlanWindow?
    /// Every later window, in order. Mid-period windows without changes are left out.
    var windows: [PlanWindow] = []
    var targets: [UUID: Double] = [:]
    /// Extra seconds a child's target carries because of the season adjustment.
    var boosts: [UUID: Double] = [:]
    var expected: [UUID: Double] = [:]
    /// The plain formula: players on field × match length ÷ players who came.
    var fairShare: Double = 0
    var notes: [String] = []
}

/// Builds the substitution plan. Pure and deterministic: the same request always gives
/// the same plan, which is what makes a replan after an injury trustworthy.
enum FairTimeEngine {

    private struct Segment {
        let start: MatchInstant
        let end: Double
        let isWindow: Bool
        var duration: Double { max(0, end - start.offset) }
        var isPeriodStart: Bool { start.offset == 0 }
    }

    static func plan(_ request: PlanRequest) -> SubPlan {
        let format = request.format
        let formation = format.formation
        let players = request.players
        let byID = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
        let segments = schedule(request)

        // MARK: Keepers
        // Keepers are settled period by period before anything else, so the time a child
        // will spend in goal later is reserved now and not handed out twice.
        var keeperPlan: [Int: UUID] = [:]
        var keeperNotes: [String] = []
        var simulatedKept: [UUID: Set<Int>] = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.keptGoalPeriods) })
        var plannedKeeper: UUID? = request.currentLineup[0]
        for period in Array(Set(segments.map(\.start.period))).sorted() {
            let opensFresh = segments.contains { $0.start.period == period && $0.isPeriodStart && $0.isWindow }
            guard opensFresh else {
                if let current = request.currentLineup[0], byID[current]?.departed == false {
                    keeperPlan[period] = current
                }
                continue
            }
            let periodStart = MatchInstant(period: period, offset: 0)
            let available = players.filter { !$0.departed && ($0.availableFrom.map { periodStart >= $0 } ?? true) }
            let pick = chooseKeeper(
                available: available,
                format: format,
                matchKeeper: plannedKeeper,
                keptGoal: simulatedKept,
                room: { -(byID[$0]?.played ?? 0) - Double(simulatedKept[$0]?.count ?? 0) * format.periodSeconds }
            )
            guard let id = pick.id else { continue }
            keeperPlan[period] = id
            plannedKeeper = id
            simulatedKept[id, default: []].insert(period)
            if pick.fallback, let name = byID[id]?.name {
                keeperNotes.append("No one marked Can Play Goalkeeper is available — \(name) keeps goal in the \(format.periods.name(of: period)).")
            }
        }

        func committed(_ id: UUID, after index: Int) -> Double {
            var total = 0.0
            for position in segments.indices where position > index && keeperPlan[segments[position].start.period] == id {
                total += segments[position].duration
            }
            return total
        }

        // MARK: Targets
        let remainingTotal = segments.reduce(0) { $0 + $1.duration }
        let playedTotal = players.reduce(0) { $0 + $1.played }
        let slotSeconds = Double(format.playersOnField) * remainingTotal + playedTotal

        var low: [UUID: Double] = [:]
        var high: [UUID: Double] = [:]
        for player in players {
            let open = player.departed ? 0 : segments
                .filter { segment in player.availableFrom.map { segment.start >= $0 } ?? true }
                .reduce(0) { $0 + $1.duration }
            high[player.id] = player.played + open
            low[player.id] = min(high[player.id] ?? 0, player.played + committed(player.id, after: -1))
        }

        let average = request.squadSeasonAverage
        let limit = max(0, request.seasonAdjustmentLimit)
        var weights: [UUID: Double] = [:]
        for player in players {
            var boost = 0.0
            if average > 0 && limit > 0 {
                boost = min(limit, max(0, (average - player.seasonSeconds) / average))
            }
            weights[player.id] = 1 + boost
        }
        let equalWeights = Dictionary(uniqueKeysWithValues: players.map { ($0.id, 1.0) })
        let targets = waterFill(ids: players.map(\.id), weights: weights, low: low, high: high, total: slotSeconds)
        let unboosted = waterFill(ids: players.map(\.id), weights: equalWeights, low: low, high: high, total: slotSeconds)
        var boosts: [UUID: Double] = [:]
        for player in players {
            let extra = (targets[player.id] ?? 0) - (unboosted[player.id] ?? 0)
            if extra > 0.5 { boosts[player.id] = extra }
        }

        // MARK: Walk the windows
        var assigned = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.played) })
        var lines: [UUID: [PitchLine: Double]] = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.lineSecondsThisMatch) })
        var keptGoal: [UUID: Set<Int>] = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0.keptGoalPeriods) })
        var previous = request.currentLineup.filter { byID[$0.value] != nil }
        var startLineup: [Int: UUID] = previous
        var opening: PlanWindow?
        var windows: [PlanWindow] = []
        var cursor = 0

        /// What a child still needs from outfield play, after time already reserved in goal.
        func remaining(_ id: UUID) -> Double {
            (targets[id] ?? 0) - (assigned[id] ?? 0) - committed(id, after: cursor)
        }

        /// Outfield time still open to a child from the current segment on: not before
        /// arriving, and not in a period already promised to that child in goal.
        func opportunity(_ id: UUID) -> Double {
            guard let player = byID[id], !player.departed else { return 0 }
            var total = 0.0
            for position in segments.indices where position >= cursor {
                let segment = segments[position]
                if let from = player.availableFrom, segment.start < from { continue }
                if keeperPlan[segment.start.period] == id { continue }
                total += segment.duration
            }
            return total
        }

        /// Need divided by chance. A child whose remaining chances are few goes first,
        /// even when someone else has more minutes still to come.
        func urgency(_ id: UUID) -> Double {
            let need = remaining(id)
            let chance = opportunity(id)
            if chance <= 0 { return need > 0 ? .greatestFiniteMagnitude : need }
            return need / chance
        }

        for (index, segment) in segments.enumerated() {
            cursor = index
            let available = players.filter { player in
                !player.departed && (player.availableFrom.map { segment.start >= $0 } ?? true)
            }
            let availableIDs = Set(available.map(\.id))
            var lineup: [Int: UUID]

            if segment.isWindow {
                // Goalkeeper first: the keeper changes only at the start of a period, or
                // when the one in goal is no longer available.
                var keeper = previous[0].flatMap { availableIDs.contains($0) ? $0 : nil }
                if segment.isPeriodStart, let planned = keeperPlan[segment.start.period], availableIDs.contains(planned) {
                    keeper = planned
                } else if segment.isPeriodStart || keeper == nil {
                    keeper = chooseKeeper(
                        available: available,
                        format: format,
                        matchKeeper: keeper,
                        keptGoal: keptGoal,
                        room: remaining
                    ).id
                }

                let previousIDs = Set(previous.values)
                let pool = available.filter { $0.id != keeper }
                let need = min(formation.outfieldSlots.count, pool.count)
                let chosen = pool.sorted { a, b in
                    let ua = urgency(a.id), ub = urgency(b.id)
                    if abs(ua - ub) > 0.005 { return ua > ub }
                    let aOn = previousIDs.contains(a.id), bOn = previousIDs.contains(b.id)
                    if aOn != bOn { return aOn }
                    let ra = remaining(a.id), rb = remaining(b.id)
                    if abs(ra - rb) > 1 { return ra > rb }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }.prefix(need)

                lineup = [:]
                if let keeper { lineup[0] = keeper }
                let slots = chooseSlots(formation: formation, count: chosen.count, previous: previous, chosen: Set(chosen.map(\.id)))
                let placed = assign(
                    players: Array(chosen),
                    slots: slots,
                    previous: previous,
                    lines: lines,
                    rotation: request.positionRotation,
                    periodStart: segment.isPeriodStart
                )
                for (slot, id) in placed { lineup[slot] = id }
            } else {
                lineup = previous.filter { availableIDs.contains($0.value) }
                fillHoles(&lineup, formation: formation, available: available, remaining: remaining)
            }

            if index == 0 {
                startLineup = lineup
                if segment.isWindow {
                    opening = diff(from: request.currentLineup, to: lineup, at: segment.start)
                }
            } else {
                let window = diff(from: previous, to: lineup, at: segment.start)
                if window.hasChanges || segment.isPeriodStart { windows.append(window) }
            }

            for (slot, id) in lineup {
                let line = formation.line(of: slot)
                assigned[id, default: 0] += segment.duration
                lines[id, default: [:]][line, default: 0] += segment.duration
                if slot == 0 { keptGoal[id, default: []].insert(segment.start.period) }
            }
            previous = lineup
        }

        var plan = SubPlan()
        plan.startLineup = startLineup
        plan.opening = opening
        plan.windows = windows
        plan.targets = targets
        plan.boosts = boosts
        plan.expected = assigned
        let attending = max(1, players.count)
        plan.fairShare = min(format.matchSeconds, Double(format.playersOnField) * format.matchSeconds / Double(attending))
        let periodsAhead = Set(segments.map(\.start.period))
        let keepers = Set(periodsAhead.compactMap { keeperPlan[$0] })
        let wholeMatchKeeper = !format.goalkeeperRotates && keepers.count == 1 && keeperPlan.count == periodsAhead.count ? keepers.first : nil
        plan.notes = notes(for: request, expected: assigned, boosts: boosts, keeperNotes: keeperNotes, wholeMatchKeeper: wholeMatchKeeper)
        return plan
    }

    // MARK: - Schedule

    private static func schedule(_ request: PlanRequest) -> [Segment] {
        let format = request.format
        let length = format.periodSeconds
        let offsets = format.windowOffsets()
        var segments: [Segment] = []
        guard request.now.period < format.periods.count else { return [] }
        for period in request.now.period..<format.periods.count {
            let start = period == request.now.period ? request.now.offset : 0
            guard start < length else { continue }
            let cuts = offsets.filter { offset in
                let instant = MatchInstant(period: period, offset: offset)
                return offset > start && (request.consumedUpTo.map { instant > $0 } ?? true)
            }
            let marks = [start] + cuts
            for (index, mark) in marks.enumerated() {
                let end = index + 1 < marks.count ? marks[index + 1] : length
                let isWindow = segments.isEmpty ? !request.lineupIsFixed : true
                segments.append(Segment(start: MatchInstant(period: period, offset: mark), end: end, isWindow: isWindow))
            }
        }
        return segments
    }

    // MARK: - Targets

    /// Finds targets that add up to `total`, each proportional to its weight, clamped between
    /// what the child has already played and what the child can still possibly play.
    static func waterFill(ids: [UUID], weights: [UUID: Double], low: [UUID: Double], high: [UUID: Double], total: Double) -> [UUID: Double] {
        let lowSum = ids.reduce(0) { $0 + (low[$1] ?? 0) }
        let highSum = ids.reduce(0) { $0 + (high[$1] ?? 0) }
        if ids.isEmpty { return [:] }
        if total <= lowSum { return low }
        if total >= highSum { return high }

        func fill(_ lambda: Double) -> [UUID: Double] {
            var result: [UUID: Double] = [:]
            for id in ids {
                let lo = low[id] ?? 0
                let hi = max(lo, high[id] ?? 0)
                result[id] = min(hi, max(lo, lambda * (weights[id] ?? 1)))
            }
            return result
        }

        let minWeight = max(0.01, ids.map { weights[$0] ?? 1 }.min() ?? 1)
        var lower = 0.0
        var upper = (ids.map { high[$0] ?? 0 }.max() ?? total) / minWeight + 1
        for _ in 0..<80 {
            let mid = (lower + upper) / 2
            let sum = fill(mid).values.reduce(0, +)
            if sum < total { lower = mid } else { upper = mid }
        }
        return fill(upper)
    }

    // MARK: - Goalkeeper

    private static func chooseKeeper(
        available: [PlanPlayer],
        format: MatchFormat,
        matchKeeper: UUID?,
        keptGoal: [UUID: Set<Int>],
        room: (UUID) -> Double
    ) -> (id: UUID?, fallback: Bool) {
        if !format.goalkeeperRotates, let matchKeeper, available.contains(where: { $0.id == matchKeeper }) {
            return (matchKeeper, false)
        }
        let candidates = available.filter(\.canKeepGoal)
        guard !candidates.isEmpty else {
            let fallback = available.sorted { a, b in
                let ra = room(a.id), rb = room(b.id)
                if abs(ra - rb) > 1 { return ra > rb }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }.first
            return (fallback?.id, fallback != nil)
        }
        let best = candidates.sorted { a, b in
            let ka = keptGoal[a.id]?.count ?? 0, kb = keptGoal[b.id]?.count ?? 0
            if ka != kb { return ka < kb }
            let sa = a.seasonLineSeconds[.goalkeeper] ?? 0, sb = b.seasonLineSeconds[.goalkeeper] ?? 0
            if abs(sa - sb) > 1 { return sa < sb }
            let ra = room(a.id), rb = room(b.id)
            if abs(ra - rb) > 1 { return ra > rb }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }.first
        return (best?.id, false)
    }

    // MARK: - Slots

    /// With fewer players than outfield places, keep the places already occupied by those
    /// staying on, then fill from the back: defence before midfield before attack.
    private static func chooseSlots(formation: Formation, count: Int, previous: [Int: UUID], chosen: Set<UUID>) -> [FormationSlot] {
        let outfield = formation.outfieldSlots
        guard count < outfield.count else { return outfield }
        let order: [PitchLine: Int] = [.defence: 0, .midfield: 1, .attack: 2]
        let sorted = outfield.sorted { a, b in
            let keepA = previous[a.index].map { chosen.contains($0) } ?? false
            let keepB = previous[b.index].map { chosen.contains($0) } ?? false
            if keepA != keepB { return keepA }
            if a.line != b.line { return (order[a.line] ?? 3) < (order[b.line] ?? 3) }
            return abs(a.x - 0.5) < abs(b.x - 0.5)
        }
        return Array(sorted.prefix(count))
    }

    private static func assign(
        players: [PlanPlayer],
        slots: [FormationSlot],
        previous: [Int: UUID],
        lines: [UUID: [PitchLine: Double]],
        rotation: Bool,
        periodStart: Bool
    ) -> [Int: UUID] {
        guard !players.isEmpty, players.count == slots.count else { return [:] }
        var cost: [[Double]] = []
        for player in players {
            var row: [Double] = []
            let seasonTotal = max(1, player.seasonLineSeconds.values.reduce(0, +))
            for slot in slots {
                let prefers = player.preferred.isEmpty || player.preferred.contains(slot.line)
                let stays = previous[slot.index] == player.id
                var value = 0.0
                if rotation {
                    value += prefers ? 0 : 1
                    value += (lines[player.id]?[slot.line] ?? 0) / 300
                    value += (player.seasonLineSeconds[slot.line] ?? 0) / seasonTotal * 2
                    if stays && !periodStart { value -= 1.5 }
                } else {
                    value += prefers ? 0 : 4
                    if stays { value -= 6 }
                }
                row.append(value)
            }
            cost.append(row)
        }
        let columns = Hungarian.solve(cost)
        var result: [Int: UUID] = [:]
        for (row, column) in columns.enumerated() {
            result[slots[column].index] = players[row].id
        }
        return result
    }

    /// Fills empty places in a lineup that otherwise holds, e.g. straight after an injury.
    private static func fillHoles(_ lineup: inout [Int: UUID], formation: Formation, available: [PlanPlayer], remaining: (UUID) -> Double) {
        let order: [PitchLine: Int] = [.goalkeeper: 0, .defence: 1, .midfield: 2, .attack: 3]
        let holes = formation.slots
            .filter { lineup[$0.index] == nil }
            .sorted { (order[$0.line] ?? 4, abs($0.x - 0.5)) < (order[$1.line] ?? 4, abs($1.x - 0.5)) }
        for slot in holes {
            let used = Set(lineup.values)
            let bench = available.filter { !used.contains($0.id) }
            let best = bench.max { a, b in
                score(a, for: slot.line, remaining: remaining) < score(b, for: slot.line, remaining: remaining)
            }
            if let best { lineup[slot.index] = best.id }
        }
        // Nobody left on the bench and the goal is empty: the best-suited outfield player
        // moves into goal rather than leaving it open.
        if lineup[0] == nil, !lineup.isEmpty {
            let outfield = lineup.filter { $0.key != 0 }
            let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
            let mover = outfield.max { a, b in
                let ka = byID[a.value]?.canKeepGoal == true ? 1 : 0
                let kb = byID[b.value]?.canKeepGoal == true ? 1 : 0
                if ka != kb { return ka < kb }
                // Otherwise an attacker goes in, so the gap opens furthest from our goal.
                return formation.line(of: a.key) != .attack && formation.line(of: b.key) == .attack
            }
            if let mover {
                lineup[mover.key] = nil
                lineup[0] = mover.value
            }
        }
    }

    private static func score(_ player: PlanPlayer, for line: PitchLine, remaining: (UUID) -> Double) -> Double {
        var value = remaining(player.id)
        if line == .goalkeeper {
            value += player.canKeepGoal ? 3600 : 0
        } else if !(player.preferred.isEmpty || player.preferred.contains(line)) {
            value -= 90
        }
        return value
    }

    private static func diff(from old: [Int: UUID], to new: [Int: UUID], at instant: MatchInstant) -> PlanWindow {
        let oldIDs = Set(old.values)
        let newIDs = Set(new.values)
        let oldSlot = Dictionary(old.map { ($0.value, $0.key) }, uniquingKeysWith: { a, _ in a })
        let comingOn = new.sorted { $0.key < $1.key }.map(\.value).filter { !oldIDs.contains($0) }
        let goingOff = old.sorted { $0.key < $1.key }.map(\.value).filter { !newIDs.contains($0) }
        let moved = new.sorted { $0.key < $1.key }.compactMap { slot, id -> UUID? in
            guard let was = oldSlot[id], was != slot else { return nil }
            return id
        }
        return PlanWindow(instant: instant, lineup: new, comingOn: comingOn, goingOff: goingOff, moved: moved)
    }

    // MARK: - Notes

    private static func notes(for request: PlanRequest, expected: [UUID: Double], boosts: [UUID: Double], keeperNotes: [String], wholeMatchKeeper: UUID?) -> [String] {
        var notes: [String] = []
        let fieldSize = request.format.playersOnField
        let active = request.players.filter { !$0.departed }
        guard !active.isEmpty else { return notes }

        if active.count <= fieldSize {
            if active.count < fieldSize {
                notes.append("Only \(active.count) here for \(fieldSize)-a-side — everyone plays the whole match.")
            } else {
                notes.append("Exactly \(fieldSize) here — everyone plays the whole match.")
            }
        } else {
            var fromStart = active.filter { $0.availableFrom == nil }
            var who = fromStart.count == active.count ? "Everyone" : "Everyone here from kick-off"
            if let keeper = wholeMatchKeeper, let name = active.first(where: { $0.id == keeper })?.name {
                notes.append("\(name) keeps goal for the whole match.")
                fromStart.removeAll { $0.id == keeper }
                who = "Everyone else"
            }
            let minutes = fromStart.map { Int(((expected[$0.id] ?? 0) / 60).rounded()) }
            if let low = minutes.min(), let high = minutes.max() {
                notes.append(low == high ? "\(who) plays about \(low) minutes." : "\(who) plays between \(low) and \(high) minutes.")
            }
        }

        var grouped: [Int: [String]] = [:]
        for player in active {
            let extra = Int(((boosts[player.id] ?? 0) / 60).rounded())
            if extra >= 1 { grouped[extra, default: []].append(player.name) }
        }
        for extra in grouped.keys.sorted(by: >) {
            let names = grouped[extra]!.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            let verb = names.count == 1 ? "gets" : "get"
            let unit = extra == 1 ? "minute" : "minutes"
            notes.append("\(listed(names)) \(verb) \(extra) extra \(unit) to make up for earlier matches.")
        }

        for player in active.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            guard let from = player.availableFrom else { continue }
            let minute = Int((from.nominalClock(periodSeconds: request.format.periodSeconds) / 60).rounded())
            let gets = Int(((expected[player.id] ?? 0) / 60).rounded())
            notes.append("\(player.name) is due at \(minute)′ and gets about \(gets) minutes from then.")
        }
        notes.append(contentsOf: keeperNotes)
        return notes
    }

    static func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }
}

/// Minimum-cost assignment (Kuhn–Munkres with potentials) for a square cost matrix.
/// Returns, for each row, the column it is assigned to.
enum Hungarian {
    static func solve(_ cost: [[Double]]) -> [Int] {
        let n = cost.count
        guard n > 0 else { return [] }
        let infinity = Double.greatestFiniteMagnitude / 4
        var u = [Double](repeating: 0, count: n + 1)
        var v = [Double](repeating: 0, count: n + 1)
        var p = [Int](repeating: 0, count: n + 1)
        var way = [Int](repeating: 0, count: n + 1)
        for i in 1...n {
            p[0] = i
            var j0 = 0
            var minv = [Double](repeating: infinity, count: n + 1)
            var used = [Bool](repeating: false, count: n + 1)
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = infinity
                var j1 = 0
                for j in 1...n where !used[j] {
                    let current = cost[i0 - 1][j - 1] - u[i0] - v[j]
                    if current < minv[j] {
                        minv[j] = current
                        way[j] = j0
                    }
                    if minv[j] < delta {
                        delta = minv[j]
                        j1 = j
                    }
                }
                for j in 0...n {
                    if used[j] {
                        u[p[j]] += delta
                        v[j] -= delta
                    } else {
                        minv[j] -= delta
                    }
                }
                j0 = j1
            } while p[j0] != 0
            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }
        var result = [Int](repeating: 0, count: n)
        for j in 1...n where p[j] > 0 {
            result[p[j] - 1] = j - 1
        }
        return result
    }
}
