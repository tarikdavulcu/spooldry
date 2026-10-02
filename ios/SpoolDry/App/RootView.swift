import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKeys.onboardingDone) private var onboardingDone = false

    var body: some View {
        @Bindable var model = model
        Group {
            if onboardingDone {
                MainTabView()
            } else {
                OnboardingView { onboardingDone = true }
            }
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $model.showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $model.showDeviceSetup) {
            DeviceSetupView()
        }
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            DashboardView()
                .tabItem { Label("Dryer", systemImage: "thermometer.and.liquid.waves") }
                .tag(AppTab.dashboard)
            ProfilesView()
                .tabItem { Label("Profiles", systemImage: "list.bullet.rectangle") }
                .tag(AppTab.profiles)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppTab.history)
            DevicesView()
                .tabItem { Label("Device", systemImage: "cpu") }
                .tag(AppTab.device)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}
