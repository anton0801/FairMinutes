import SwiftUI
import UIKit

enum LoadState: Equatable {
    case loading
    case ready
    case failed(String)
}

/// What the coach sees before a drag on the field is committed.
struct MovePreview: Identifiable, Equatable {
    let id = UUID()
    let playerID: UUID
    let slot: Int?
    let title: String
    let lines: [String]
    let nextWindow: String?
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var data = AppData()
    @Published var saveError: String?
    /// Set when a match has just been recorded, so the summary opens by itself.
    @Published var justFinishedMatchID: UUID?

    private let file: DataFile
    private let writer = DispatchQueue(label: "fairminutes.writer", qos: .utility)
    private var ticker: Timer?

    init(file: DataFile = .standard) {
        self.file = file
    }

    // MARK: - Loading

    func load() {
        loadState = .loading
        let file = self.file
        Task {
            let result: Result<AppData?, Error> = await Task.detached(priority: .userInitiated) {
                Result { try file.load() }
            }.value
            switch result {
            case .success(let stored):
                data = stored ?? AppData()
                ensureSeason()
                loadState = .ready
                refreshLiveState()
            case .failure(let error):
                loadState = .failed(error.localizedDescription)
            }
        }
    }

    /// Keeps the unreadable file aside and starts with an empty squad.
    func startFresh() {
        file.setAside()
        data = AppData()
        ensureSeason()
        loadState = .ready
        refreshLiveState()
    }

    private func persist() {
        let snapshot = data
        let file = self.file
        writer.async { [weak self] in
            do {
                try file.save(snapshot)
                Task { @MainActor in self?.saveError = nil }
            } catch {
                let message = error.localizedDescription
                Task { @MainActor in self?.saveError = message }
            }
        }
    }

    func retrySave() { persist() }

    // MARK: - Derived

    var season: Season {
        data.seasons.last ?? Season(name: Self.seasonName(for: Date()), startedOn: Date())
    }

    var ledger: SeasonLedger { SeasonLedger(season: season, squad: data.squad) }
    var planningContext: PlanningContext { ledger.planningContext(settings: data.settings) }

    var squadByName: [Player] {
        data.squad.sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
    }

    func player(_ id: UUID) -> Player? { data.squad.first { $0.id == id } }
    func name(_ id: UUID) -> String { player(id)?.firstName ?? "Player" }

    func record(_ id: UUID) -> MatchRecord? {
        for season in data.seasons.reversed() {
            if let match = season.matches.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    static func seasonName(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let first = month >= 7 ? year : year - 1
        return String(format: "%d–%02d", first, (first + 1) % 100)
    }

    private func ensureSeason() {
        if data.seasons.isEmpty {
            data.seasons.append(Season(name: Self.seasonName(for: Date()), startedOn: Date()))
        }
    }

    // MARK: - Squad

    func validate(_ player: Player) -> String? {
        let name = player.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Add a first name." }
        if name.count > 24 { return "Keep the name to 24 letters or fewer." }
        if !(0...99).contains(player.shirtNumber) { return "Shirt numbers run from 0 to 99." }
        if let other = data.squad.first(where: { $0.shirtNumber == player.shirtNumber && $0.id != player.id }) {
            return "Number \(player.shirtNumber) is already \(other.firstName)'s."
        }
        return nil
    }

    func nextFreeNumber() -> Int {
        let taken = Set(data.squad.map(\.shirtNumber))
        return (1...99).first { !taken.contains($0) } ?? 0
    }

    @discardableResult
    func save(_ player: Player) -> String? {
        var clean = player
        clean.firstName = player.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.notes = player.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = validate(clean) { return problem }
        if let index = data.squad.firstIndex(where: { $0.id == clean.id }) {
            data.squad[index] = clean
        } else {
            data.squad.append(clean)
        }
        replanIfNeeded()
        persist()
        return nil
    }

    func deletionBlocker(for id: UUID) -> String? {
        guard let match = data.liveMatch, match.isAttending(id) else { return nil }
        return "\(name(id)) is part of today's match. Finish or cancel the match first."
    }

    func delete(_ id: UUID) {
        guard deletionBlocker(for: id) == nil else { return }
        data.squad.removeAll { $0.id == id }
        data.liveMatch?.attendance[id] = nil
        persist()
    }

    // MARK: - Team, format, settings

    func setTeamName(_ name: String) {
        data.teamName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        persist()
    }

    /// A new format takes over the next match. If today's match has not kicked off yet,
    /// it is re-planned in the new format straight away.
    func setFormat(_ format: MatchFormat) {
        data.format = format
        if var match = data.liveMatch, match.phase == .ready {
            match.format = format
            match.lineup = [:]
            match.manualLineup = false
            match.replan(planningContext, now: Date(), fixed: false)
            data.liveMatch = match
        }
        persist()
    }

    func setSettings(_ settings: TeamSettings) {
        data.settings = settings
        replanIfNeeded()
        persist()
    }

    private func replanIfNeeded() {
        guard var match = data.liveMatch, match.phase != .finished else { return }
        match.replan(planningContext, now: Date(), fixed: match.isUnderway || match.manualLineup)
        data.liveMatch = match
    }

    // MARK: - Onboarding

    func completeOnboarding(teamName: String, format: MatchFormat, squad: [Player], date: Date, opponent: String, attendance: [UUID: Attendance]) {
        data.teamName = teamName.trimmingCharacters(in: .whitespacesAndNewlines)
        data.format = format
        data.squad = squad
        ensureSeason()
        data.onboardingComplete = true
        setUpMatch(date: date, opponent: opponent, attendance: attendance)
    }

    // MARK: - Match set-up

    func setUpMatch(date: Date, opponent: String, attendance: [UUID: Attendance]) {
        var match = LiveMatch(
            date: date,
            opponent: opponent.trimmingCharacters(in: .whitespacesAndNewlines),
            format: data.format,
            attendance: attendance
        )
        match.replan(planningContext, now: Date(), fixed: false)
        data.liveMatch = match
        justFinishedMatchID = nil
        persist()
        refreshLiveState()
    }

    func cancelMatch() {
        data.liveMatch = nil
        persist()
        refreshLiveState()
    }

    // MARK: - Live match

    private func live(_ change: (inout LiveMatch, PlanningContext, Date) -> Void) {
        guard var match = data.liveMatch else { return }
        change(&match, planningContext, Date())
        if match.phase == .finished {
            finish(match)
        } else {
            data.liveMatch = match
        }
        persist()
        refreshLiveState()
    }

    func startPeriod() { live { match, context, now in match.start(context, now: now) } }
    func pause() { live { match, _, now in match.pause(now: now) } }
    func resume() { live { match, _, now in match.resume(now: now) } }
    func endPeriod() { live { match, context, now in match.endPeriod(context, now: now) } }

    func confirm(_ window: PlanWindow) {
        live { match, context, now in match.confirm(window, context, now: now) }
    }

    func subNow() {
        live { match, context, now in
            guard let window = match.nextWindowThisPeriod else { return }
            match.confirm(window, context, now: now)
        }
    }

    func move(_ id: UUID, to slot: Int?) { live { match, context, now in match.move(id, to: slot, context, now: now) } }
    func depart(_ id: UUID, reason: DepartureReason) { live { match, context, now in match.depart(id, reason: reason, context, now: now) } }
    func returnToPlay(_ id: UUID) { live { match, context, now in match.returnToPlay(id, context, now: now) } }
    func arrive(_ id: UUID) { live { match, context, now in match.arrive(id, context, now: now) } }

    func setAttendance(_ id: UUID, _ value: Attendance) {
        live { match, context, now in match.setAttendance(id, value, context, now: now) }
    }

    private func finish(_ match: LiveMatch) {
        let record = match.record(squad: data.squad)
        ensureSeason()
        data.seasons[data.seasons.count - 1].matches.append(record)
        data.liveMatch = nil
        justFinishedMatchID = record.id
    }

    /// Works out, without changing anything, what a drag on the field would do.
    func previewMove(_ id: UUID, to slot: Int?) -> MovePreview? {
        guard let before = data.liveMatch, before.isAvailable(id) else { return nil }
        var after = before
        let now = Date()
        after.move(id, to: slot, planningContext, now: now)
        guard after.lineup != before.lineup else { return nil }

        let wasOn = Set(before.lineup.values)
        let isOn = Set(after.lineup.values)
        let off = wasOn.subtracting(isOn)
        let on = isOn.subtracting(wasOn)
        var involved = off.union(on)
        involved.insert(id)
        if let slot, let occupant = before.lineup[slot] { involved.insert(occupant) }

        let title: String
        if !off.isEmpty || !on.isEmpty {
            let offNames = FairTimeEngine.listed(off.map(name).sorted())
            let onNames = FairTimeEngine.listed(on.map(name).sorted())
            switch (off.isEmpty, on.isEmpty) {
            case (false, false): title = "\(offNames) off, \(onNames) on"
            case (false, true): title = "\(offNames) to the bench"
            default: title = "\(onNames) on"
            }
        } else if let slot, let occupant = before.lineup[slot] {
            title = "\(name(id)) and \(name(occupant)) swap places"
        } else {
            title = "\(name(id)) moves"
        }

        var lines: [String] = []
        for pid in involved.sorted(by: { name($0).localizedCaseInsensitiveCompare(name($1)) == .orderedAscending }) {
            let gap = (after.plan.expected[pid] ?? 0) - (after.plan.targets[pid] ?? 0)
            let minutes = Minutes.whole(abs(gap))
            if gap <= -60 {
                lines.append("This leaves \(name(pid)) \(minutes) \(minutes == 1 ? "minute" : "minutes") under target.")
            } else if gap >= 60 {
                lines.append("This puts \(name(pid)) \(minutes) \(minutes == 1 ? "minute" : "minutes") over target.")
            }
        }
        if lines.isEmpty {
            lines.append("Everyone involved still ends within a minute of target.")
        }

        var next: String?
        if after.isUnderway {
            if let window = after.plan.windows.first {
                next = "Next window: \(Minutes.clock(window.instant.nominalClock(periodSeconds: after.format.periodSeconds)))."
            } else {
                next = "No more windows in this match."
            }
        } else {
            next = "The change is made at kick-off."
        }
        return MovePreview(playerID: id, slot: slot, title: title, lines: lines, nextWindow: next)
    }

    // MARK: - Season

    func startNewSeason(named name: String) {
        guard data.liveMatch?.isUnderway != true else { return }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !data.seasons.isEmpty { data.seasons[data.seasons.count - 1].endedOn = Date() }
        data.seasons.append(Season(name: clean.isEmpty ? Self.seasonName(for: Date()) : clean, startedOn: Date()))
        replanIfNeeded()
        persist()
    }

    func renameSeason(_ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !data.seasons.isEmpty else { return }
        data.seasons[data.seasons.count - 1].name = clean
        persist()
    }

    func deleteMatch(_ id: UUID) {
        for index in data.seasons.indices {
            data.seasons[index].matches.removeAll { $0.id == id }
        }
        if justFinishedMatchID == id { justFinishedMatchID = nil }
        replanIfNeeded()
        persist()
    }

    func deleteAllData() {
        stopTicker()
        UIApplication.shared.isIdleTimerDisabled = false
        // On the writer queue, so a save still in flight cannot bring the file back.
        let file = self.file
        writer.async { file.wipe() }
        data = AppData()
        ensureSeason()
        justFinishedMatchID = nil
        saveError = nil
    }

    // MARK: - Clock alerts

    /// Keeps the screen awake for the whole match and runs the alert check while the
    /// clock is running. The check itself only compares against the device clock.
    func refreshLiveState() {
        let phase = data.liveMatch?.phase
        UIApplication.shared.isIdleTimerDisabled = phase == .running || phase == .paused || phase == .interval
        if phase == .running {
            startTicker()
            tick()
        } else {
            stopTicker()
        }
    }

    private func startTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    func tick() {
        guard var match = data.liveMatch, match.phase == .running else { return }
        let now = Date()
        let haptics = data.settings.hapticAlerts
        var changed = false
        if let window = match.nextWindowThisPeriod {
            let until = match.secondsUntil(window, at: now)
            let warn = "warn-\(window.id)"
            let due = "due-\(window.id)"
            if until <= 60, until > 0, !match.alerted.contains(warn) {
                match.alerted.insert(warn)
                if haptics { Haptics.changeComing() }
                changed = true
            }
            if until <= 0, !match.alerted.contains(due) {
                match.alerted.insert(due)
                match.alerted.insert(warn)
                if haptics { Haptics.changeDue() }
                changed = true
            }
        }
        let over = "over-\(match.period)"
        if match.periodElapsed(at: now) >= match.format.periodSeconds, !match.alerted.contains(over) {
            match.alerted.insert(over)
            if haptics { Haptics.periodOver() }
            changed = true
        }
        if changed {
            data.liveMatch = match
            persist()
        }
    }
}

/// The three buzzes a coach learns to recognise with the phone in a pocket.
enum Haptics {
    static func changeComing() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func changeDue() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { generator.impactOccurred() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { generator.impactOccurred() }
    }

    static func periodOver() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
