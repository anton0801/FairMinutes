import SwiftUI

/// The squad as a rack of shirts, in name order.
struct SquadPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState

    var body: some View {
        let players = store.squadByName
        VStack(spacing: 0) {
            SummaryStrip(eyebrow: store.data.teamName.isEmpty ? "Squad" : store.data.teamName, headline: players.count == 1 ? "1 player" : "\(players.count) players") {
                PrimaryButton(title: "add", systemImage: "plus", height: 50) { screen.push(.editPlayer(nil)) }
                    .frame(width: 112)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ListStateView(
                        phase: phase(players),
                        emptyTitle: "No players yet",
                        emptyMessage: "First names and shirt numbers are all the app needs.",
                        emptyAction: ("add a player", { screen.push(.editPlayer(nil)) }),
                        retry: store.load
                    ) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 10)], spacing: 16) {
                            ForEach(players) { player in
                                Button {
                                    screen.push(.editPlayer(player.id))
                                } label: {
                                    PlayerToken(player: player, tone: tone(player), progress: nil, width: 58)
                                        .frame(maxWidth: .infinity)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(player.firstName), number \(player.shirtNumber)")
                                .accessibilityHint("Edit player")
                            }
                        }
                    }
                    NoteLine(text: "Keep first names only. These are children's details, so the app never asks for a surname, photo or birthday — and none of it leaves this phone.", tint: Palette.yellow)
                    if store.data.liveMatch != nil {
                        Text("Blue shirts are on the field, yellow on the bench.")
                            .font(Typeface.caption)
                            .foregroundColor(Palette.muted)
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.bottom, 40)
            }
        }
    }

    private func phase(_ players: [Player]) -> ListPhase {
        switch store.loadState {
        case .loading: return .loading
        case .failed(let message): return .failed(message)
        case .ready: return players.isEmpty ? .empty : .ready
        }
    }

    private func tone(_ player: Player) -> JerseyTone {
        guard let match = store.data.liveMatch else { return .plain }
        if !match.isAvailable(player.id) { return match.isAwaited(player.id) ? .awaited : .away }
        return match.isOnField(player.id) ? .onField : .bench
    }
}

struct PlayerEditorPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var screen: ScreenState
    let playerID: UUID?

    @State private var draft = Player(firstName: "", shirtNumber: 1)
    @State private var numberText = ""
    @State private var problem: String?
    @State private var prepared = false
    @State private var confirmDelete = false

    private var isNew: Bool { playerID == nil || store.player(playerID!) == nil }

    var body: some View {
        PanelScaffold(title: isNew ? "new player" : draft.firstName.isEmpty ? "player" : draft.firstName, keepsCase: !isNew && !draft.firstName.isEmpty, subtitle: isNew ? "Added to the squad on this phone" : "No. \(draft.shirtNumber)", onBack: screen.pop) {
            JerseyView(number: Int(numberText) ?? 0, tone: .bench, width: 64)
        } content: {
            LabeledField(label: "First Name", hint: "First name only — no surname needed.") {
                OutlinedTextField(placeholder: "e.g. Maya", text: $draft.firstName, submitLabel: .next, autofocus: playerID == nil)
            }
            LabeledField(label: "Shirt Number", hint: "Each number is used once in the squad.") {
                OutlinedTextField(placeholder: "0–99", text: $numberText, keyboard: .numberPad, capitalization: .never)
                    .onChange(of: numberText) { value in
                        let digits = String(value.filter(\.isNumber).prefix(2))
                        if digits != value { numberText = digits }
                    }
            }
            LabeledField(label: "Preferred Positions", hint: "Leave all off if anywhere is fine. Used only to place children, never to rank them.") {
                HStack(spacing: 8) {
                    ForEach(PitchLine.outfield) { line in
                        let on = draft.preferredLines.contains(line)
                        Button {
                            Haptics.tap()
                            if on { draft.preferredLines.remove(line) } else { draft.preferredLines.insert(line) }
                        } label: {
                            Text(line.title.lowercased())
                                .font(.system(size: Typeface.scaled(16), weight: .heavy).italic())
                                .foregroundColor(on ? .white : Palette.anchor)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Palette.blue : Palette.ground))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Palette.blue : Palette.anchor, lineWidth: Metric.stroke))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            SwitchRow(title: "Can Play Goalkeeper", detail: "Keepers are chosen from these children, in turn.", isOn: $draft.canPlayGoalkeeper)
            LabeledField(label: "Notes for Coach", hint: "Only you see this. E.g. inhaler in the kit bag.") {
                TextEditor(text: $draft.notes)
                    .font(Typeface.body)
                    .foregroundColor(Palette.anchor)
                    .frame(minHeight: 88)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous).fill(Palette.ground))
                    .overlay(RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous).strokeBorder(Palette.anchor, lineWidth: Metric.stroke))
            }
            if let problem {
                NoteLine(text: problem, tint: Palette.red)
            }
            PrimaryButton(title: isNew ? "add to squad" : "save", systemImage: "checkmark", action: save)
            if !isNew {
                SecondaryButton(title: "season minutes", systemImage: "chart.bar.fill", height: 48) {
                    if let id = playerID { screen.push(.seasonPlayer(id), in: .season) }
                }
                SecondaryButton(title: "remove from squad", tint: Palette.red, height: 48) {
                    if let id = playerID, let blocker = store.deletionBlocker(for: id) {
                        problem = blocker
                    } else {
                        confirmDelete = true
                    }
                }
            }
        }
        .onAppear(perform: prepare)
        .confirmationDialog("Remove \(draft.firstName) from the squad?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let id = playerID { store.delete(id) }
                screen.pop()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Past matches keep \(draft.firstName)'s minutes. The shirt number becomes free.")
        }
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        if let id = playerID, let player = store.player(id) {
            draft = player
        } else {
            draft = Player(firstName: "", shirtNumber: store.nextFreeNumber())
        }
        numberText = "\(draft.shirtNumber)"
    }

    private func save() {
        guard let number = Int(numberText) else {
            problem = "Add a shirt number from 0 to 99."
            return
        }
        draft.shirtNumber = number
        if let issue = store.save(draft) {
            problem = issue
            return
        }
        Haptics.tap()
        screen.pop()
    }
}
