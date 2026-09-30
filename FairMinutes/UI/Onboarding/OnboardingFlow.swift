import SwiftUI

/// Four screens that explain, two that set up. No skip: the last one builds the first plan.
struct OnboardingFlow: View {
    @EnvironmentObject private var store: AppStore
    @State private var step = 0
    @State private var forward = true

    @State private var teamName = ""
    @State private var format = MatchFormat()
    @State private var players: [Player] = []
    @State private var date = Date()
    @State private var opponent = ""
    @State private var attendance: [UUID: Attendance] = [:]

    private let stepCount = 6

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ZStack {
                page
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Palette.ground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        #if DEBUG
        .onAppear {
            let requested = UserDefaults.standard.integer(forKey: "FMOnboardingStep")
            if requested > 0 { step = min(stepCount - 1, requested) }
        }
        #endif
    }

    // MARK: Chrome

    private var topBar: some View {
        HStack(spacing: 12) {
            if step > 0 {
                BackLink { go(to: step - 1) }
            } else {
                Color.clear.frame(width: 60, height: 44)
            }
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? [Palette.blue, Palette.red, Palette.yellow][index % 3] : Palette.marking)
                        .frame(width: index == step ? 22 : 12, height: 5)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(stepCount)")
            Spacer()
            Color.clear.frame(width: 60, height: 44)
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let hint = blocker {
                Text(hint)
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            PrimaryButton(title: buttonTitle, systemImage: step == stepCount - 1 ? "list.number" : nil, isEnabled: blocker == nil) {
                if step == stepCount - 1 { finish() } else { go(to: step + 1) }
            }
        }
        .padding(.horizontal, Metric.gutter)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Palette.ground.ignoresSafeArea())
    }

    private var buttonTitle: String {
        switch step {
        case 0...2: return "next"
        case 3: return "set up my squad"
        case 4: return "next match"
        default: return "build the plan"
        }
    }

    private var blocker: String? {
        switch step {
        case 4:
            if players.count < format.playersOnField {
                let missing = format.playersOnField - players.count
                return "Add at least \(format.playersOnField) players for \(format.playersOnField)-a-side — \(missing) more."
            }
            return nil
        case 5:
            let here = players.filter { attendance[$0.id] != .absent }.count
            return here == 0 ? "Mark at least one child as here." : nil
        default:
            return nil
        }
    }

    private func go(to next: Int) {
        forward = next > step
        if next == 5 {
            for player in players where attendance[player.id] == nil { attendance[player.id] = .present }
            attendance = attendance.filter { id, _ in players.contains { $0.id == id } }
        }
        withAnimation(.interpolatingSpring(stiffness: 260, damping: 26)) { step = next }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
    }

    private func finish() {
        store.completeOnboarding(teamName: teamName, format: format, squad: players, date: date, opponent: opponent, attendance: attendance)
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case 0:
            ExplainerPage(
                title: "Every Child Counts the Minutes",
                text: "Parents remember every minute their child spends on the bench. In the middle of a match, a coach can't. Fair Minutes keeps the count for you — and never rates anyone."
            ) { BenchIllustration() }
        case 1:
            ExplainerPage(
                title: "Fair Is a Number",
                text: "Players on the field × match length ÷ children who came. Seven a side, 40 minutes, ten children: 28 minutes each. The plan puts everyone as close to that as the substitution windows allow."
            ) { FormulaIllustration() }
        case 2:
            ExplainerPage(
                title: "The App Remembers Last Week",
                text: "A child who fell behind in earlier matches gets a little more next time — up to 20% more — until the squad is level again. Late arrivals and early departures are counted to the minute."
            ) { CatchUpIllustration() }
        case 3:
            ExplainerPage(
                title: "Your Phone, Your Squad",
                text: "No account and no sign-up. First names and shirt numbers stay on this phone only — nothing is uploaded, synced or backed up to a server. A summary leaves only when you share it."
            ) { PrivacyIllustration() }
        case 4:
            SquadStep(teamName: $teamName, format: $format, players: $players)
        default:
            NextMatchStep(players: players, format: format, date: $date, opponent: $opponent, attendance: $attendance)
        }
    }
}

private struct ExplainerPage<Illustration: View>: View {
    let title: String
    let text: String
    @ViewBuilder var illustration: Illustration

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                illustration
                    .frame(maxWidth: .infinity)
                    .frame(height: 290)
                    .padding(.top, 12)
                VStack(alignment: .leading, spacing: 12) {
                    ScreenTitle(text: title, size: 32)
                    KitStripes()
                    Text(text)
                        .font(Typeface.body)
                        .foregroundColor(Palette.anchor)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Set-up steps

private struct SquadStep: View {
    @Binding var teamName: String
    @Binding var format: MatchFormat
    @Binding var players: [Player]

    @State private var name = ""
    @State private var number = "1"
    @State private var problem: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    ScreenTitle(text: "Your Squad", size: 32)
                    KitStripes()
                }
                .padding(.top, 8)
                LabeledField(label: "Team Name") {
                    OutlinedTextField(placeholder: "e.g. Lions U10", text: $teamName)
                }
                LabeledField(label: "Players on Field") {
                    ChoiceRow(options: MatchFormat.fieldSizes, selection: Binding(
                        get: { format.playersOnField },
                        set: { format.adopt(fieldSize: $0) }
                    )) { "\($0)" }
                }
                LabeledField(label: "Halves or Quarters") {
                    ChoiceRow(options: PeriodStructure.allCases, selection: $format.periods) { $0.title.lowercased() }
                }
                CountStepper(label: "Period Length", value: $format.periodMinutes, range: 5...45, format: { "\($0) min" })
                Text("\(format.periods.count) × \(format.periodMinutes) = \(format.matchMinutes)-minute match. Substitutions every \(format.rollingEveryMinutes) minutes; change the rule later in Settings.")
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeading("players", detail: "\(players.count) added")
                    Text("First name and shirt number. No surnames — these are children's details.")
                        .font(Typeface.caption)
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("First name", text: $name)
                            .font(Typeface.body)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .onSubmit(add)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 52)
                            .overlay(RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous).strokeBorder(Palette.anchor, lineWidth: Metric.stroke))
                        TextField("No.", text: $number)
                            .font(.system(size: Typeface.scaled(17), weight: .heavy).monospacedDigit())
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 60, height: 52)
                            .overlay(RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous).strokeBorder(Palette.anchor, lineWidth: Metric.stroke))
                            .onChange(of: number) { value in
                                let digits = String(value.filter(\.isNumber).prefix(2))
                                if digits != value { number = digits }
                            }
                            .accessibilityLabel("Shirt number")
                        Button(action: add) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .heavy))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous).fill(Palette.blue))
                        }
                        .accessibilityLabel("Add player")
                    }
                    if let problem {
                        NoteLine(text: problem, tint: Palette.red)
                    }
                    if players.isEmpty {
                        HStack(spacing: 12) {
                            EmptyPitch(width: 44)
                            Text("The squad is empty. Add the first child above.")
                                .font(Typeface.body)
                                .foregroundColor(Palette.muted)
                        }
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 14) {
                            ForEach(players.sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }) { player in
                                PlayerToken(player: player, tone: .bench, progress: nil, width: 50)
                                    .frame(maxWidth: .infinity)
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            players.removeAll { $0.id == player.id }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 10, weight: .heavy))
                                                .foregroundColor(.white)
                                                .frame(width: 22, height: 22)
                                                .background(Circle().fill(Palette.anchor))
                                                .frame(width: 44, height: 44)
                                                .contentShape(Rectangle())
                                        }
                                        .offset(x: 10, y: -14)
                                        .accessibilityLabel("Remove \(player.firstName)")
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private func add() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            problem = "Type a first name first."
            return
        }
        guard clean.count <= 24 else {
            problem = "Keep the name to 24 letters or fewer."
            return
        }
        guard let value = Int(number), (0...99).contains(value) else {
            problem = "Add a shirt number from 0 to 99."
            return
        }
        if let other = players.first(where: { $0.shirtNumber == value }) {
            problem = "Number \(value) is already \(other.firstName)'s."
            return
        }
        players.append(Player(firstName: clean, shirtNumber: value))
        problem = nil
        name = ""
        let taken = Set(players.map(\.shirtNumber))
        number = "\((1...99).first { !taken.contains($0) } ?? 0)"
        nameFocused = true
        Haptics.tap()
    }
}

private struct NextMatchStep: View {
    let players: [Player]
    let format: MatchFormat
    @Binding var date: Date
    @Binding var opponent: String
    @Binding var attendance: [UUID: Attendance]

    var body: some View {
        let sorted = players.sorted { $0.firstName.localizedCaseInsensitiveCompare($1.firstName) == .orderedAscending }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    ScreenTitle(text: "Your Next Match", size: 32)
                    KitStripes()
                }
                .padding(.top, 8)
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
                    SectionHeading("who came today")
                    Text("Tap a shirt: here → not here → late. The substitution plan is built as soon as you continue.")
                        .font(Typeface.caption)
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    AttendanceGrid(players: sorted, attendance: $attendance)
                    LateArrivals(players: sorted, attendance: $attendance, matchMinutes: format.matchMinutes)
                }
            }
            .padding(.horizontal, Metric.gutter)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
}
