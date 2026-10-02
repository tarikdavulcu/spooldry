import StoreKit
import SpoolDryKit
import SwiftUI

/// "SpoolDry Lifetime": one-time purchase, no subscription. The price is StoreKit's localized price.
struct PaywallView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let benefits: [(icon: String, text: LocalizedStringKey)] = [
        ("infinity", "Unlimited drying sessions"),
        ("platter.filled.top.iphone", "Live Activity & Dynamic Island on every bake"),
        ("list.bullet.rectangle", "Custom filament profiles"),
        ("clock.arrow.circlepath", "Full history & statistics"),
        ("cpu", "Multiple dryers"),
        ("sparkles", "All future improvements"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 10) {
                        Image("PaywallHero")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 112, height: 112)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .accessibilityHidden(true)
                        Text("SpoolDry Lifetime").font(.largeTitle.weight(.bold))
                        Text(priceText)
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel(Text("Price: \(priceText)"))
                        Text("ONE-TIME PURCHASE").font(.subheadline.weight(.bold)).tracking(1.5)
                        Text("No subscription.").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .multilineTextAlignment(.center)

                    if !model.store.hasLifetime {
                        Text("You've used \(min(model.sessions.usedFreeSessions, FreeTierPolicy.freeSessionLimit)) of \(FreeTierPolicy.freeSessionLimit) free drying sessions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(benefits, id: \.icon) { b in
                                Label {
                                    Text(b.text)
                                } icon: {
                                    Image(systemName: b.icon).foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }

                    statusView

                    Button {
                        Task { await model.store.purchase() }
                    } label: {
                        if model.store.purchaseState == .purchasing {
                            ProgressView()
                        } else {
                            model.store.product == nil ? Text("Unlock Lifetime") : Text("Unlock Lifetime for \(priceText)")
                        }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.store.hasLifetime || model.store.purchaseState == .purchasing)

                    Button("Restore Purchases") { Task { await model.store.restore() } }
                        .font(.subheadline)

                    Text("Payment is charged to your Apple Account. One purchase unlocks SpoolDry on this Apple Account; there are no recurring charges.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    HStack(spacing: 16) {
                        Link("Privacy Policy", destination: SharedConstants.privacyURL)
                        Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    }
                    .font(.caption)
                }
                .padding(24)
            }
            .spoolDryBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { if model.store.product == nil { await model.store.loadProduct() } }
            .onChange(of: model.store.hasLifetime) { _, owned in if owned { dismiss() } }
        }
    }

    /// Localized StoreKit price. Never hard-coded.
    private var priceText: String {
        model.store.product?.displayPrice ?? "…"
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.store.purchaseState {
        case .pending:
            Label("Purchase pending approval.", systemImage: "hourglass").font(.footnote)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Theme.danger)
        case .purchased:
            Label("SpoolDry Lifetime is active. Thank you!", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.success)
        default:
            if model.store.productLoadFailed {
                Label("The App Store is not reachable right now. Please try again later.", systemImage: "wifi.exclamationmark")
                    .font(.footnote)
            }
        }
    }
}
