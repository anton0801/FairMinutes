import SwiftUI

struct RootView: View {
    @StateObject private var store = AppStore()
    @State private var splashFinished = false

    var body: some View {
        ZStack {
            if !splashFinished || store.loadState == .loading {
                SplashView()
                    .transition(.opacity)
            } else if case .failed(let message) = store.loadState {
                LoadFailureView(message: message)
                    .transition(.opacity)
            } else if !store.data.onboardingComplete {
                OnboardingFlow()
                    .transition(.opacity)
            } else {
                MainScreen()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: splashFinished)
        .animation(.easeInOut(duration: 0.35), value: store.data.onboardingComplete)
        .environmentObject(store)
        .preferredColorScheme(.light)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .tint(Palette.blue)
        .task {
            store.load()
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            splashFinished = true
        }
    }
}

/// Pitch lines draw themselves, a shirt lands on the centre spot, the name follows.
struct SplashView: View {
    @State private var drawn = false
    @State private var landed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.ground.ignoresSafeArea()
            VStack(spacing: 26) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.pitch)
                        .frame(width: 150, height: 210)
                        .opacity(drawn ? 1 : 0)
                    PitchMarkings()
                        .trim(from: 0, to: drawn ? 1 : 0)
                        .stroke(Palette.marking, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 150, height: 210)
                    JerseyView(number: 7, tone: .onField, width: 72)
                        .offset(y: landed ? 0 : -46)
                        .opacity(landed ? 1 : 0)
                }
                VStack(spacing: 10) {
                    Text("fair minutes")
                        .font(Typeface.title(36))
                        .foregroundColor(Palette.anchor)
                    KitStripes(width: 22, height: 5)
                }
                .opacity(landed ? 1 : 0)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Fair Minutes")
        .onAppear {
            if reduceMotion {
                drawn = true
                landed = true
                return
            }
            withAnimation(.easeInOut(duration: 0.8)) { drawn = true }
            withAnimation(.interpolatingSpring(stiffness: 260, damping: 20).delay(0.55)) { landed = true }
        }
    }
}

/// The saved file could not be opened. Nothing is deleted from here without asking.
struct LoadFailureView: View {
    @EnvironmentObject private var store: AppStore
    let message: String
    @State private var confirmFresh = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            EmptyPitch(width: 96)
            ScreenTitle(text: "the squad didn't open")
            Text(message)
                .font(Typeface.body)
                .foregroundColor(Palette.anchor)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your data has not been changed or deleted.")
                .font(Typeface.body)
                .foregroundColor(Palette.muted)
            PrimaryButton(title: "try again", systemImage: "arrow.clockwise", action: store.load)
            SecondaryButton(title: "start fresh", height: 48) { confirmFresh = true }
            Spacer()
        }
        .padding(.horizontal, Metric.gutter)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(Palette.ground.ignoresSafeArea())
        .confirmationDialog("Start with an empty squad?", isPresented: $confirmFresh, titleVisibility: .visible) {
            Button("Start Fresh") { store.startFresh() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The unreadable file is kept aside on this phone, not deleted.")
        }
    }
}
