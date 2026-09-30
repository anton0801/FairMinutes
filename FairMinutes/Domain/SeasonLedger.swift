import Foundation

/// One child's season, in the only terms this app keeps: minutes, attendance, places tried.
struct SeasonLine: Identifiable, Equatable {
    let id: UUID
    let name: String
    let number: Int
    let playedSeconds: Double
    /// Seconds the child could have played in the matches attended.
    let possibleSeconds: Double
    let matchesAttended: Int
    let matchesTotal: Int
    let lineSeconds: [PitchLine: Double]

    var share: Double { possibleSeconds > 0 ? min(1, playedSeconds / possibleSeconds) : 0 }
    var linesTried: [PitchLine] { PitchLine.allCases.filter { (lineSeconds[$0] ?? 0) >= 30 } }
}

struct SeasonInsights: Equatable {
    static let matchesNeeded = 3

    let matchesPlayed: Int
    /// Most season minutes minus fewest, across the current squad.
    let spreadSeconds: Double
    let averageSeconds: Double
    let belowAverage: [String]
    let averageLinesTried: Double
    let onlyOneLine: Int
    let attendanceRate: Double

    var hasEnoughData: Bool { matchesPlayed >= Self.matchesNeeded }
}

/// Reads a season. Everything here is derived; nothing is stored twice.
struct SeasonLedger {
    let season: Season
    let squad: [Player]

    private var matches: [MatchRecord] { season.matches }

    func playedSeconds(_ id: UUID) -> Double {
        matches.reduce(0) { sum, match in sum + (match.entries.first { $0.playerID == id }?.playedSeconds ?? 0) }
    }

    func lineSeconds(_ id: UUID) -> [PitchLine: Double] {
        var result: [PitchLine: Double] = [:]
        for match in matches {
            guard let entry = match.entries.first(where: { $0.playerID == id }) else { continue }
            for (line, seconds) in entry.lineSeconds { result[line, default: 0] += seconds }
        }
        return result
    }

    /// Team average of banked minutes. Zero until a match has been recorded.
    var squadAverage: Double {
        guard !matches.isEmpty, !squad.isEmpty else { return 0 }
        return squad.reduce(0) { $0 + playedSeconds($1.id) } / Double(squad.count)
    }

    func line(for player: Player) -> SeasonLine {
        var possible = 0.0
        var attended = 0
        for match in matches {
            guard let entry = match.entries.first(where: { $0.playerID == player.id }), entry.attended else { continue }
            attended += 1
            possible += entry.availableSeconds
        }
        return SeasonLine(
            id: player.id,
            name: player.firstName,
            number: player.shirtNumber,
            playedSeconds: playedSeconds(player.id),
            possibleSeconds: possible,
            matchesAttended: attended,
            matchesTotal: matches.count,
            lineSeconds: lineSeconds(player.id)
        )
    }

    /// Always alphabetical. The season list must never read as a ranking.
    var lines: [SeasonLine] {
        squad
            .sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
            .map(line(for:))
    }

    var insights: SeasonInsights {
        let rows = lines
        let seconds = rows.map(\.playedSeconds)
        let average = squadAverage
        let below = rows
            .filter { average > 0 && $0.playedSeconds < average - 30 }
            .map(\.name)
        let tried = rows.map { Double($0.linesTried.count) }
        let attendedTotal = rows.reduce(0) { $0 + $1.matchesAttended }
        let possibleAttendance = max(1, rows.count * matches.count)
        return SeasonInsights(
            matchesPlayed: matches.count,
            spreadSeconds: (seconds.max() ?? 0) - (seconds.min() ?? 0),
            averageSeconds: average,
            belowAverage: below,
            averageLinesTried: tried.isEmpty ? 0 : tried.reduce(0, +) / Double(tried.count),
            onlyOneLine: rows.filter { $0.linesTried.count == 1 }.count,
            attendanceRate: Double(attendedTotal) / Double(possibleAttendance)
        )
    }

    func planningContext(settings: TeamSettings) -> PlanningContext {
        var seasonSeconds: [UUID: Double] = [:]
        var seasonLines: [UUID: [PitchLine: Double]] = [:]
        for player in squad {
            seasonSeconds[player.id] = playedSeconds(player.id)
            seasonLines[player.id] = lineSeconds(player.id)
        }
        return PlanningContext(
            squad: squad,
            seasonSeconds: seasonSeconds,
            seasonLineSeconds: seasonLines,
            squadAverage: squadAverage,
            settings: settings
        )
    }
}

/// Text a coach can send to one family. It only ever contains that one child.
enum ParentSummary {
    static func match(_ record: MatchRecord, entry: PlayerMatchEntry, teamName: String) -> String {
        let date = record.date.formatted(date: .abbreviated, time: .omitted)
        var lines: [String] = []
        let versus = record.opponent.isEmpty ? "Match" : "vs \(record.opponent)"
        lines.append("\(entry.firstName) — \(teamName.isEmpty ? "" : teamName + ", ")\(versus), \(date)")
        guard entry.attended else {
            lines.append("Not at this match.")
            return lines.joined(separator: "\n")
        }
        let matchMinutes = Int((record.totalSeconds / 60).rounded())
        lines.append("Played \(Minutes.text(entry.playedSeconds)) of the \(matchMinutes)-minute match.")
        lines.append("Fair share for this match: \(Minutes.text(entry.targetSeconds)).")
        let places = PitchLine.allCases.compactMap { line -> String? in
            guard let seconds = entry.lineSeconds[line], seconds >= 30 else { return nil }
            return "\(line.title) \(Minutes.short(seconds))"
        }
        if !places.isEmpty { lines.append("Played in: \(places.joined(separator: " · ")).") }
        if let arrived = entry.arrivedAt {
            lines.append("Arrived at \(Minutes.clockMinute(arrived, format: record.format)).")
        }
        if let departure = entry.departure {
            lines.append("\(departure.reason == .injury ? "Went off injured" : "Left early") at \(Minutes.clockMinute(departure.at, format: record.format)).")
        }
        lines.append("")
        lines.append("Minutes only — no ratings, no comparisons. Sent from Fair Minutes.")
        return lines.joined(separator: "\n")
    }

    static func season(_ season: Season, line: SeasonLine, teamName: String) -> String {
        var lines: [String] = []
        lines.append("\(line.name) — \(teamName.isEmpty ? "" : teamName + ", ")\(season.name)")
        lines.append("Matches attended: \(line.matchesAttended) of \(line.matchesTotal).")
        lines.append("Minutes played: \(Int((line.playedSeconds / 60).rounded())).")
        if line.possibleSeconds > 0 {
            lines.append("That is \(Int((line.share * 100).rounded()))% of the minutes in the matches \(line.name) attended.")
        }
        let tried = line.linesTried.map(\.title)
        if !tried.isEmpty { lines.append("Positions tried: \(tried.joined(separator: ", ")).") }
        lines.append("")
        lines.append("Minutes only — no ratings, no comparisons. Sent from Fair Minutes.")
        return lines.joined(separator: "\n")
    }
}

/// Minute formatting shared by the domain text and the screens.
enum Minutes {
    static func whole(_ seconds: Double) -> Int { Int((seconds / 60).rounded()) }

    static func text(_ seconds: Double) -> String {
        let value = whole(seconds)
        return value == 1 ? "1 minute" : "\(value) minutes"
    }

    static func short(_ seconds: Double) -> String { "\(whole(seconds)) min" }

    /// mm:ss, used for the match clock.
    static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// m:ss for short countdowns.
    static func countdown(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Signed minutes against target: "+2", "−3", "±0".
    static func signed(_ seconds: Double) -> String {
        let value = whole(seconds)
        if value == 0 { return "±0" }
        return value > 0 ? "+\(value)" : "−\(abs(value))"
    }

    static func clockMinute(_ instant: MatchInstant, format: MatchFormat) -> String {
        "\(Int(instant.nominalClock(periodSeconds: format.periodSeconds) / 60))′"
    }
}
