import SwiftUI

/// Onboarding pictures are drawn from the app's own parts — pitch lines and shirts —
/// and carry numbers only. No invented children appear anywhere in the app.
private struct IllustrationPitch: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.pitch)
            PitchMarkings().stroke(Palette.marking, lineWidth: Metric.line)
        }
    }
}

struct BenchIllustration: View {
    @State private var minutes = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            ZStack {
                IllustrationPitch()
                VStack(spacing: 26) {
                    JerseyView(number: 9, tone: .onField, width: 40)
                    HStack(spacing: 30) {
                        JerseyView(number: 6, tone: .onField, width: 40)
                        JerseyView(number: 8, tone: .onField, width: 40)
                    }
                    JerseyView(number: 1, tone: .onField, width: 40)
                }
            }
            .frame(width: 150, height: 214)
            VStack(alignment: .leading, spacing: 10) {
                Text("\(minutes)′")
                    .font(Typeface.minutes(56))
                    .foregroundColor(Palette.red)
                Text("on the bench")
                    .font(.system(size: 14, weight: .heavy).italic())
                    .foregroundColor(Palette.anchor)
                HStack(spacing: 10) {
                    VStack(spacing: 4) {
                        JerseyView(number: 4, tone: .bench, width: 44)
                        MinutesBar(progress: 0.2, width: 38)
                    }
                    VStack(spacing: 4) {
                        JerseyView(number: 11, tone: .bench, width: 44)
                        MinutesBar(progress: 0.35, width: 38)
                    }
                }
            }
        }
        .onReceive(timer) { _ in
            guard !reduceMotion else { minutes = 12; return }
            minutes = minutes >= 12 ? 0 : minutes + 1
        }
        .onAppear { if reduceMotion { minutes = 12 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Four shirts on the pitch, two on the bench, and a bench clock counting minutes.")
    }
}

struct FormulaIllustration: View {
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .top, spacing: 8) {
                term("7", "on the field")
                symbol("×")
                term("40", "minutes")
                symbol("÷")
                term("10", "came today")
            }
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("=")
                    .font(Typeface.minutes(40))
                    .foregroundColor(Palette.anchor)
                Text("28")
                    .font(Typeface.minutes(64))
                    .foregroundColor(Palette.blue)
                Text("min each")
                    .font(.system(size: 16, weight: .heavy).italic())
                    .foregroundColor(Palette.anchor)
            }
            HStack(spacing: 6) {
                ForEach(1...10, id: \.self) { number in
                    VStack(spacing: 4) {
                        JerseyView(number: number, tone: number <= 7 ? .onField : .bench, width: 26)
                        MinutesBar(progress: 1, width: 22, height: 3)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("7 on the field times 40 minutes divided by 10 who came equals 28 minutes each.")
    }

    private func term(_ value: String, _ caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Typeface.minutes(44))
                .foregroundColor(Palette.anchor)
            Text(caption)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Palette.muted)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 62)
    }

    private func symbol(_ text: String) -> some View {
        Text(text)
            .font(Typeface.minutes(32))
            .foregroundColor(Palette.red)
            .padding(.top, 6)
    }
}

struct CatchUpIllustration: View {
    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: 34) {
            column(number: 4, seasonShare: 0.62, extra: true)
            column(number: 9, seasonShare: 1, extra: false)
            column(number: 2, seasonShare: 0.97, extra: false)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .interpolatingSpring(stiffness: 120, damping: 14).delay(0.3)) { grown = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Three shirts with season minutes. The one furthest behind gets 3 extra minutes in the next plan.")
    }

    private func column(number: Int, seasonShare: Double, extra: Bool) -> some View {
        VStack(spacing: 8) {
            if extra {
                Text("+3 min")
                    .font(.system(size: 15, weight: .heavy).italic())
                    .foregroundColor(Palette.anchor)
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Palette.yellow)
                    .overlay(Rectangle().stroke(Palette.anchor, lineWidth: 2))
                    .scaleEffect(grown ? 1 : 0.4)
                    .opacity(grown ? 1 : 0)
            } else {
                Color.clear.frame(height: 28)
            }
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6).fill(Palette.pitch)
                RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.marking, lineWidth: Metric.line)
                VStack(spacing: 0) {
                    if extra {
                        Palette.yellow.frame(height: grown ? 26 : 0)
                    }
                    (extra ? Palette.red : Palette.blue).frame(height: 150 * seasonShare)
                }
                .frame(width: 26)
                .padding(.bottom, 2)
            }
            .frame(width: 48, height: 184)
            JerseyView(number: number, tone: extra ? .nextChange : .onField, width: 52)
        }
    }
}

struct PrivacyIllustration: View {
    var body: some View {
        ZStack {
            IllustrationPitch()
                .frame(width: 190, height: 266)
            Circle()
                .fill(Palette.yellow)
                .overlay(Circle().strokeBorder(Palette.anchor, lineWidth: Metric.stroke))
                .frame(width: 84, height: 84)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundColor(Palette.anchor)
                )
            JerseyView(number: 3, tone: .onField, width: 44).offset(x: -62, y: -86)
            JerseyView(number: 7, tone: .bench, width: 44).offset(x: 62, y: -60)
            JerseyView(number: 5, tone: .onField, width: 44).offset(x: -54, y: 84)
            JerseyView(number: 10, tone: .bench, width: 44).offset(x: 60, y: 96)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shirts around a lock in the centre circle: the squad stays on this phone.")
    }
}
