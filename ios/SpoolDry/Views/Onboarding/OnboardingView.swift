import SwiftUI

/// Four screens maximum, skippable.
struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Page {
        let symbol: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(symbol: "humidity.fill", title: "Know When Your Filament Is Dry.",
             body: "SpoolDry tracks drying sessions for PLA through PA-CF, with typical guidance for engineering polymers."),
        Page(symbol: "antenna.radiowaves.left.and.right", title: "Connect Your ESP32 Dryer.",
             body: "Your iPhone talks directly to the dryer over Bluetooth. No account, no cloud, works offline."),
        Page(symbol: "thermometer.and.liquid.waves", title: "Track Temperature & Humidity.",
             body: "Live chamber temperature and relative humidity, with a full history of every bake."),
        Page(symbol: "platter.filled.top.iphone", title: "Monitor Drying From Your Lock Screen.",
             body: "Live Activities and the Dynamic Island show the real dryer state and remaining time."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip") { onFinish() }
                    .padding()
            }
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 24) {
                        Spacer()
                        ZStack {
                            Circle().fill(Theme.heroGradient).frame(width: 180, height: 180)
                            Image(systemName: pages[i].symbol)
                                .font(.system(size: 72, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .accessibilityHidden(true)
                        Text(pages[i].title)
                            .font(.largeTitle.weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(pages[i].body)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 28)
                    .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button {
                if page < pages.count - 1 {
                    if reduceMotion { page += 1 } else { withAnimation { page += 1 } }
                } else {
                    onFinish()
                }
            } label: {
                page < pages.count - 1 ? Text("Continue") : Text("Get Started")
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(24)
        }
        .spoolDryBackground()
    }
}
