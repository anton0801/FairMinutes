import Foundation

// MARK: - Pitch lines

/// The four bands of the pitch a child can play in. Minutes are tracked per line so the
/// coach can see who has tried what — never how well anyone played there.
enum PitchLine: String, Codable, CaseIterable, Identifiable, Hashable {
    case goalkeeper, defence, midfield, attack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goalkeeper: return "Goalkeeper"
        case .defence: return "Defence"
        case .midfield: return "Midfield"
        case .attack: return "Attack"
        }
    }

    var short: String {
        switch self {
        case .goalkeeper: return "GK"
        case .defence: return "DEF"
        case .midfield: return "MID"
        case .attack: return "ATT"
        }
    }

    static let outfield: [PitchLine] = [.defence, .midfield, .attack]
}

// MARK: - Squad

struct Player: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var firstName: String
    var shirtNumber: Int
    var preferredLines: Set<PitchLine> = []
    var canPlayGoalkeeper: Bool = false
    var notes: String = ""
}

struct TeamSettings: Codable, Equatable {
    /// The most a child's target can grow to make up for earlier matches (0.2 = 20%).
    var seasonAdjustmentLimit: Double = 0.2
    var positionRotation: Bool = false
    var hapticAlerts: Bool = true
}

// MARK: - Match format

enum PeriodStructure: String, Codable, CaseIterable, Identifiable {
    case halves, quarters

    var id: String { rawValue }
    var count: Int { self == .halves ? 2 : 4 }
    var title: String { self == .halves ? "Halves" : "Quarters" }

    func name(of index: Int) -> String {
        switch self {
        case .halves: return index == 0 ? "1st half" : "2nd half"
        case .quarters: return "Quarter \(index + 1)"
        }
    }

    func shortName(of index: Int) -> String {
        switch self {
        case .halves: return index == 0 ? "H1" : "H2"
        case .quarters: return "Q\(index + 1)"
        }
    }
}

enum SubstitutionRule: String, Codable, CaseIterable, Identifiable {
    case rolling, atBreaksOnly, atFixedWindows

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rolling: return "Rolling"
        case .atBreaksOnly: return "At Breaks Only"
        case .atFixedWindows: return "At Fixed Windows"
        }
    }

    var explanation: String {
        switch self {
        case .rolling: return "Changes every few minutes, whenever the ball is out."
        case .atBreaksOnly: return "Changes only between periods."
        case .atFixedWindows: return "Changes at set points inside each period, like a water break."
        }
    }
}

struct MatchFormat: Codable, Equatable {
    static let fieldSizes = [5, 7, 8, 9, 11]

    var playersOnField: Int = 7
    var shapeID: String = "2-3-1"
    var periods: PeriodStructure = .halves
    var periodMinutes: Int = 20
    var substitutionRule: SubstitutionRule = .rolling
    var rollingEveryMinutes: Int = 5
    var fixedWindowsPerPeriod: Int = 1
    var goalkeeperRotates: Bool = true

    var periodSeconds: Double { Double(periodMinutes * 60) }
    var matchMinutes: Int { periods.count * periodMinutes }
    var matchSeconds: Double { Double(matchMinutes * 60) }
    var formation: Formation { Formation.shape(id: shapeID, playersOnField: playersOnField) }

    /// Offsets (seconds into a period) at which the lineup may change. Always starts at 0.
    func windowOffsets() -> [Double] {
        let length = periodMinutes * 60
        switch substitutionRule {
        case .atBreaksOnly:
            return [0]
        case .rolling:
            let step = max(1, rollingEveryMinutes) * 60
            var offsets: [Double] = []
            var mark = 0
            // A change that would leave less than two minutes before the whistle is dropped:
            // a child brought on for ninety seconds has not really been given a turn.
            while mark < length && (mark == 0 || length - mark >= 120) {
                offsets.append(Double(mark))
                mark += step
            }
            return offsets
        case .atFixedWindows:
            let count = max(1, fixedWindowsPerPeriod)
            var offsets: [Double] = [0]
            for index in 1...count {
                let minute = (periodMinutes * index) / (count + 1)
                let seconds = Double(minute * 60)
                if seconds > 0 && seconds < Double(length) && !offsets.contains(seconds) {
                    offsets.append(seconds)
                }
            }
            return offsets
        }
    }

    /// Picks a sensible default shape and period length when the number on the field changes.
    mutating func adopt(fieldSize: Int) {
        playersOnField = fieldSize
        shapeID = Formation.options(for: fieldSize).first?.id ?? shapeID
    }
}

// MARK: - Formations

struct FormationSlot: Equatable, Hashable {
    let index: Int
    let line: PitchLine
    /// 0 = left touchline, 1 = right touchline.
    let x: Double
    /// 0 = the end we attack (top of the screen), 1 = our own goal line.
    let y: Double
}

struct Formation: Equatable, Identifiable {
    let id: String
    let playersOnField: Int
    let slots: [FormationSlot]

    var name: String { id }
    var outfieldSlots: [FormationSlot] { slots.filter { $0.line != .goalkeeper } }

    init(defence: Int, midfield: Int, attack: Int) {
        id = "\(defence)-\(midfield)-\(attack)"
        playersOnField = 1 + defence + midfield + attack
        var built: [FormationSlot] = [FormationSlot(index: 0, line: .goalkeeper, x: 0.5, y: 0.9)]
        func spread(_ count: Int) -> [Double] {
            switch count {
            case 1: return [0.5]
            case 2: return [0.3, 0.7]
            case 3: return [0.18, 0.5, 0.82]
            case 4: return [0.12, 0.37, 0.63, 0.88]
            default: return (0..<count).map { (Double($0) + 1) / (Double(count) + 1) }
            }
        }
        let rows: [(PitchLine, Int, Double)] = [(.defence, defence, 0.64), (.midfield, midfield, 0.41), (.attack, attack, 0.185)]
        for (line, count, y) in rows where count > 0 {
            for x in spread(count) {
                built.append(FormationSlot(index: built.count, line: line, x: x, y: y))
            }
        }
        slots = built
    }

    static func options(for fieldSize: Int) -> [Formation] {
        switch fieldSize {
        case 5: return [Formation(defence: 2, midfield: 1, attack: 1), Formation(defence: 1, midfield: 2, attack: 1)]
        case 7: return [Formation(defence: 2, midfield: 3, attack: 1), Formation(defence: 3, midfield: 2, attack: 1)]
        case 8: return [Formation(defence: 3, midfield: 3, attack: 1), Formation(defence: 2, midfield: 3, attack: 2)]
        case 9: return [Formation(defence: 3, midfield: 3, attack: 2), Formation(defence: 3, midfield: 2, attack: 3)]
        default: return [Formation(defence: 4, midfield: 3, attack: 3), Formation(defence: 4, midfield: 4, attack: 2)]
        }
    }

    static func shape(id: String, playersOnField: Int) -> Formation {
        let options = options(for: playersOnField)
        return options.first(where: { $0.id == id }) ?? options[0]
    }

    func line(of slot: Int) -> PitchLine {
        slots.first(where: { $0.index == slot })?.line ?? .midfield
    }
}

// MARK: - Match time

/// A point in a match, measured inside its period. Periods can run over their nominal
/// length, so a single running clock would drift from the plan; a (period, offset) pair
/// does not.
struct MatchInstant: Codable, Hashable, Comparable {
    var period: Int
    var offset: Double

    static func < (lhs: MatchInstant, rhs: MatchInstant) -> Bool {
        lhs.period != rhs.period ? lhs.period < rhs.period : lhs.offset < rhs.offset
    }

    /// The clock reading a coach would expect: in a 2 × 20 match the start of the 2nd half is 20:00.
    func nominalClock(periodSeconds: Double) -> Double {
        Double(period) * periodSeconds + offset
    }

    var key: String { "\(period)-\(Int(offset.rounded()))" }
}

// MARK: - Attendance and departures

enum Attendance: Codable, Equatable {
    case present
    case late(expectedMinute: Int)
    case absent

    var isComing: Bool { self != .absent }
}

enum DepartureReason: String, Codable {
    case injury, leftEarly

    var title: String { self == .injury ? "Injury" : "Left Early" }
    var pastTense: String { self == .injury ? "went off injured" : "left early" }
}

struct Departure: Codable, Equatable {
    var at: MatchInstant
    var reason: DepartureReason
}

// MARK: - Season records

struct PlayerMatchEntry: Codable, Identifiable, Equatable {
    var id: UUID { playerID }
    var playerID: UUID
    var firstName: String
    var shirtNumber: Int
    var attended: Bool
    var arrivedAt: MatchInstant?
    var departure: Departure?
    var playedSeconds: Double
    var targetSeconds: Double
    /// Seconds this child could have been on the field: the match from arrival to departure.
    var availableSeconds: Double
    var lineSeconds: [PitchLine: Double]

    var deviationSeconds: Double { playedSeconds - targetSeconds }
    var linesPlayed: [PitchLine] { PitchLine.allCases.filter { (lineSeconds[$0] ?? 0) >= 30 } }
}

struct MatchRecord: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var date: Date
    var opponent: String
    var format: MatchFormat
    var periodDurations: [Double]
    var entries: [PlayerMatchEntry]

    var attendees: [PlayerMatchEntry] {
        entries.filter(\.attended).sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    var totalSeconds: Double { periodDurations.reduce(0, +) }
}

struct Season: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var startedOn: Date
    var endedOn: Date?
    var matches: [MatchRecord] = []
}
