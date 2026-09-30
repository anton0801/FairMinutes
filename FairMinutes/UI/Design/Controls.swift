import SwiftUI

// MARK: - Buttons

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Blue, 58 tall, 16 radius, a yellow stripe down its left edge, heavy italic lower case.
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = Palette.blue
    var height: CGFloat = Metric.buttonHeight
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 17, weight: .bold))
                }
                Text(title.lowercased())
                    .font(height < Metric.buttonHeight ? Typeface.smallButton : Typeface.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(.white)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                ZStack(alignment: .leading) {
                    (isEnabled ? tint : Palette.anchor.opacity(0.25))
                    Palette.yellow.frame(width: 6)
                }
                .clipShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
            )
            .contentShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!isEnabled)
    }
}

/// White with a 2.5 anchor outline.
struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var tint: Color = Palette.anchor
    var height: CGFloat = Metric.buttonHeight
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 16, weight: .bold))
                }
                Text(title.lowercased())
                    .font(height < Metric.buttonHeight ? Typeface.smallButton : Typeface.button)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundColor(isEnabled ? tint : Palette.anchor.opacity(0.3))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                    .fill(Palette.ground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous)
                    .strokeBorder(isEnabled ? tint : Palette.anchor.opacity(0.2), lineWidth: Metric.stroke)
            )
            .contentShape(RoundedRectangle(cornerRadius: Metric.buttonRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .disabled(!isEnabled)
    }
}

/// A 44 × 44 outlined glyph button for headers.
struct IconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(Palette.anchor)
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(Palette.anchor, lineWidth: Metric.stroke))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(label)
    }
}

/// "‹ back" link used at the top of pushed drawer panels.
struct BackLink: View {
    var title = "back"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .heavy))
                Text(title).font(Typeface.smallButton)
            }
            .foregroundColor(Palette.blue)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(title == "back" ? "Back" : title)
    }
}

// MARK: - Fields

struct LabeledField<Content: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Typeface.label)
                .foregroundColor(Palette.muted)
            content
            if let hint {
                Text(hint)
                    .font(Typeface.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct OutlinedTextField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .words
    var submitLabel: SubmitLabel = .done
    var onSubmit: () -> Void = {}
    var autofocus = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .font(Typeface.body)
            .foregroundColor(Palette.anchor)
            .keyboardType(keyboard)
            .textInputAutocapitalization(capitalization)
            .disableAutocorrection(true)
            .submitLabel(submitLabel)
            .onSubmit(onSubmit)
            .focused($focused)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous).fill(Palette.ground))
            .overlay(
                RoundedRectangle(cornerRadius: Metric.fieldRadius, style: .continuous)
                    .strokeBorder(focused ? Palette.blue : Palette.anchor, lineWidth: Metric.stroke)
            )
            .onAppear {
                guard autofocus else { return }
                // After the drawer has finished moving, so the keyboard does not fight it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { focused = true }
            }
    }
}

/// − value + with 44-point targets.
struct CountStepper: View {
    let label: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    var format: (Int) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 0) {
            Text(label)
                .font(Typeface.body)
                .foregroundColor(Palette.anchor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            stepButton("minus", enabled: value - step >= range.lowerBound) { value = max(range.lowerBound, value - step) }
            Text(format(value))
                .font(.system(size: Typeface.scaled(19), weight: .heavy).monospacedDigit())
                .foregroundColor(Palette.anchor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 84)
            stepButton("plus", enabled: value + step <= range.upperBound) { value = min(range.upperBound, value + step) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(format(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value + step)
            case .decrement: value = max(range.lowerBound, value - step)
            @unknown default: break
            }
        }
    }

    private func stepButton(_ glyph: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tap()
        } label: {
            Image(systemName: glyph)
                .font(.system(size: 16, weight: .heavy))
                .foregroundColor(enabled ? Palette.anchor : Palette.anchor.opacity(0.25))
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(enabled ? Palette.anchor : Palette.anchor.opacity(0.2), lineWidth: Metric.stroke)
                )
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
    }
}

/// One-of-many choice laid out as a row of outlined tiles; the chosen one is solid anchor.
struct ChoiceRow<Value: Hashable>: View {
    let options: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 8) {
            ForEach(options, id: \.self) { option in
                let chosen = option == selection
                Button {
                    selection = option
                    Haptics.tap()
                } label: {
                    Text(title(option))
                        .font(.system(size: Typeface.scaled(16), weight: .heavy).italic())
                        .foregroundColor(chosen ? .white : Palette.anchor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(chosen ? Palette.anchor : Palette.ground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Palette.anchor, lineWidth: Metric.stroke)
                        )
                }
                .buttonStyle(PressStyle())
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

struct SwitchRow: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typeface.bodyBold)
                    .foregroundColor(Palette.anchor)
                if let detail {
                    Text(detail)
                        .font(Typeface.caption)
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Palette.blue)
        .frame(minHeight: 44)
    }
}

/// A plain navigational line: title, optional value, chevron. A 2pt rule underneath.
struct LinkRow: View {
    let title: String
    var value: String?
    var tint: Color = Palette.anchor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Typeface.bodyBold)
                    .foregroundColor(tint)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(Typeface.body)
                        .foregroundColor(Palette.muted)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundColor(Palette.muted)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { Palette.marking.frame(height: Metric.line) }
        }
        .buttonStyle(PressStyle())
    }
}

/// A short statement with the kit stripe on its left: used for plan notes and warnings.
struct NoteLine: View {
    let text: String
    var tint: Color = Palette.blue

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            tint.frame(width: 4).frame(maxHeight: .infinity)
            Text(text)
                .font(Typeface.body)
                .foregroundColor(Palette.anchor)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - List states

enum ListPhase: Equatable {
    case loading
    case empty
    case failed(String)
    case ready
}

/// Every list in the app goes through this: loading shows faint shirts, empty shows the
/// bare pitch, a failure says what went wrong and offers to try again.
struct ListStateView<Content: View>: View {
    let phase: ListPhase
    let emptyTitle: String
    let emptyMessage: String
    var emptyAction: (title: String, run: () -> Void)?
    var retry: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        switch phase {
        case .ready:
            content
        case .loading:
            LoadingShirts()
        case .empty:
            VStack(spacing: 14) {
                EmptyPitch(width: 84)
                Text(emptyTitle)
                    .font(Typeface.heading(20))
                    .foregroundColor(Palette.anchor)
                    .multilineTextAlignment(.center)
                Text(emptyMessage)
                    .font(Typeface.body)
                    .foregroundColor(Palette.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let emptyAction {
                    PrimaryButton(title: emptyAction.title, action: emptyAction.run)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 12) {
                NoteLine(text: message, tint: Palette.red)
                if let retry {
                    SecondaryButton(title: "try again", systemImage: "arrow.clockwise", action: retry)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

struct LoadingShirts: View {
    @State private var dim = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { index in
                JerseyShape()
                    .stroke(Palette.marking, lineWidth: Metric.stroke)
                    .frame(width: 48, height: 45)
                    .opacity(dim ? 0.35 : 1)
                    .animation(
                        reduceMotion ? nil : .easeInOut(duration: 0.7).repeatForever().delay(Double(index) * 0.2),
                        value: dim
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .onAppear { dim = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}
