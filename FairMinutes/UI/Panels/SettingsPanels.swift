import SwiftUI

struct SettingsPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    @State private var teamName = ""
    @State private var settings = TeamSettings()
    @State private var prepared = false
    @State private var confirmDelete = false
    @State private var confirmDeleteAgain = false
    @State private var exportProblem: String?

    var body: some View {
        PanelScaffold(title: "settings", subtitle: "Everything here stays on this phone", onBack: screen.pop) {
            LabeledField(label: "Team Name") {
                OutlinedTextField(placeholder: "e.g. Lions U10", text: $teamName, onSubmit: { store.setTeamName(teamName) })
            }
            VStack(alignment: .leading, spacing: 0) {
                LinkRow(title: "Match Format", value: formatSummary) { screen.push(.format) }
                LinkRow(title: "Start New Season", value: store.season.name) { screen.push(.newSeason) }
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading("fair time")
                CountStepper(
                    label: "Season Adjustment Limit",
                    value: Binding(
                        get: { Int((settings.seasonAdjustmentLimit * 100).rounded()) },
                        set: { settings.seasonAdjustmentLimit = Double($0) / 100 }
                    ),
                    range: 0...30,
                    step: 5,
                    format: { "\($0)%" }
                )
                Text("A child behind the squad's season average gets up to this much more time in the next plan. 0% turns the catch-up off.")
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                SwitchRow(title: "Position Rotation", detail: "Moves children around the lines so everyone tries different places, using what they have played this match and this season.", isOn: $settings.positionRotation)
                SwitchRow(title: "Haptic Alerts", detail: "Buzz a minute before each change, at the change, and when a period's time is up.", isOn: $settings.hapticAlerts)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionHeading("data")
                if let exportProblem {
                    NoteLine(text: exportProblem, tint: Palette.red)
                }
                SecondaryButton(title: "export season as pdf", systemImage: "doc.richtext", height: 48, isEnabled: !store.data.squad.isEmpty) {
                    do {
                        let url = try SeasonReport.make(teamName: store.data.teamName, season: store.season, ledger: store.ledger)
                        exportProblem = nil
                        ShareSheet.present([url])
                    } catch {
                        exportProblem = error.localizedDescription
                    }
                }
                LinkRow(title: "About Fair Minutes") { screen.push(.about) }
                SecondaryButton(title: "delete all app data", systemImage: "trash", tint: Palette.red, height: 48) { confirmDelete = true }
            }
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            teamName = store.data.teamName
            settings = store.data.settings
        }
        .onChange(of: settings) { store.setSettings($0) }
        .onDisappear { if teamName != store.data.teamName { store.setTeamName(teamName) } }
        .confirmationDialog("Delete all app data?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Everything", role: .destructive) { confirmDeleteAgain = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The squad, every match and every season are removed from this phone. There is no copy anywhere else.")
        }
        .alert("This cannot be undone", isPresented: $confirmDeleteAgain) {
            Button("Delete", role: .destructive) {
                store.deleteAllData()
                screen.reset()
            }
            Button("Keep My Data", role: .cancel) {}
        } message: {
            Text("Export the season as a PDF first if you want to keep the minutes.")
        }
    }

    private var formatSummary: String {
        let format = store.data.format
        return "\(format.playersOnField)-a-side · \(format.periods.count) × \(format.periodMinutes)"
    }
}

/// Players on field, halves or quarters, period length, substitution rule, keeper rule.
struct FormatEditor: View {
    @Binding var format: MatchFormat

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            LabeledField(label: "Players on Field") {
                ChoiceRow(options: MatchFormat.fieldSizes, selection: Binding(
                    get: { format.playersOnField },
                    set: { format.adopt(fieldSize: $0) }
                )) { "\($0)" }
            }
            LabeledField(label: "Shape", hint: "Defence – midfield – attack, plus the keeper.") {
                HStack(alignment: .center, spacing: 14) {
                    ChoiceRow(options: Formation.options(for: format.playersOnField).map(\.id), selection: $format.shapeID) { $0 }
                    FormationPreview(formation: format.formation)
                }
            }
            LabeledField(label: "Halves or Quarters") {
                ChoiceRow(options: PeriodStructure.allCases, selection: $format.periods) { $0.title.lowercased() }
            }
            CountStepper(label: "Period Length", value: $format.periodMinutes, range: 5...45, format: { "\($0) min" })
            Text("Match length: \(format.matchMinutes) minutes.")
                .font(Typeface.caption)
                .foregroundColor(Palette.muted)
            LabeledField(label: "Substitution Rule") {
                VStack(spacing: 8) {
                    ForEach(SubstitutionRule.allCases) { rule in
                        let chosen = rule == format.substitutionRule
                        Button {
                            Haptics.tap()
                            format.substitutionRule = rule
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Circle()
                                    .strokeBorder(Palette.anchor, lineWidth: Metric.stroke)
                                    .background(Circle().fill(chosen ? Palette.blue : Palette.ground).padding(5))
                                    .frame(width: 24, height: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.title)
                                        .font(Typeface.bodyBold)
                                        .foregroundColor(Palette.anchor)
                                    Text(rule.explanation)
                                        .font(Typeface.caption)
                                        .foregroundColor(Palette.muted)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen ? .isSelected : [])
                    }
                }
            }
            switch format.substitutionRule {
            case .rolling:
                CountStepper(label: "Change Every", value: $format.rollingEveryMinutes, range: 2...15, format: { "\($0) min" })
            case .atFixedWindows:
                CountStepper(label: "Windows per Period", value: $format.fixedWindowsPerPeriod, range: 1...3)
            case .atBreaksOnly:
                EmptyView()
            }
            SwitchRow(title: "Goalkeeper Rotates", detail: format.goalkeeperRotates ? "A new keeper each period, taken in turn from the children who can play in goal." : "One keeper for the whole match; the others share the outfield minutes.", isOn: $format.goalkeeperRotates)
        }
    }
}

/// The chosen shape as dots on a small pitch.
struct FormationPreview: View {
    let formation: Formation

    var body: some View {
        ZStack {
            Palette.pitch
            PitchMarkings(showsBoxes: false).stroke(Palette.marking, lineWidth: 1.5)
            GeometryReader { proxy in
                ForEach(formation.slots, id: \.index) { slot in
                    Circle()
                        .fill(slot.line == .goalkeeper ? Palette.yellow : Palette.blue)
                        .overlay(Circle().stroke(Palette.anchor, lineWidth: 1.5))
                        .frame(width: 9, height: 9)
                        .position(x: proxy.size.width * slot.x, y: proxy.size.height * min(0.9, slot.y))
                }
            }
        }
        .frame(width: 52, height: 72)
        .accessibilityHidden(true)
    }
}

struct FormatPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    @State private var format = MatchFormat()
    @State private var prepared = false

    var body: some View {
        PanelScaffold(title: "match format", subtitle: "Used for every match from now on", onBack: screen.pop) {
            FormatEditor(format: $format)
            if store.data.liveMatch?.isUnderway == true || store.data.liveMatch?.phase == .interval {
                NoteLine(text: "Today's match keeps its format. The new one applies from the next match.", tint: Palette.yellow)
            } else if store.data.liveMatch?.phase == .ready {
                NoteLine(text: "Today's plan is rebuilt in the new format.", tint: Palette.blue)
            }
            PrimaryButton(title: "save format", systemImage: "checkmark") {
                store.setFormat(format)
                screen.pop()
            }
        }
        .onAppear {
            guard !prepared else { return }
            prepared = true
            format = store.data.format
        }
    }
}

struct AboutPanel: View {
    @EnvironmentObject private var screen: ScreenState

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        PanelScaffold(title: "about", subtitle: "Fair Minutes \(version)", onBack: screen.pop) {
            HStack(spacing: 14) {
                JerseyView(number: 7, tone: .onField, width: 56)
                JerseyView(number: 10, tone: .bench, width: 56)
                JerseyView(number: 4, tone: .nextChange, width: 56)
            }
            aboutBlock("what it does", "Plans substitutions so every child who came plays close to the same minutes, reminds you when to change, and keeps a season of minutes you can show to families.")
            aboutBlock("how fair is worked out", "Players on the field × match length ÷ children who came. Children behind the squad's season average get a little more — never more than the limit in Settings. Late arrivals and early departures are counted exactly.")
            aboutBlock("what it never does", "No ratings, no stars, no scores, no best players, no comparing children by ability. The season list is sorted by name, not by minutes.")
            aboutBlock("where the data lives", "Only on this phone. No account, no sign-up, no servers, no analytics, and the file is kept out of device backups. A text or PDF leaves the phone only when you share it.")
            aboutBlock("the clock", "The match clock is worked out from the phone's own time, so a locked screen or a closed app does not lose a second. The screen stays awake while a match is on.")
        }
    }

    private func aboutBlock(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(title)
            Text(text)
                .font(Typeface.body)
                .foregroundColor(Palette.anchor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
