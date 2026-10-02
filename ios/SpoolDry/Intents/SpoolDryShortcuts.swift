import AppIntents

/// "Show my filament dryer" — opens SpoolDry on the dashboard (Siri, Spotlight, Shortcuts, Action button).
struct OpenDryerStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Dryer Status"
    static var description = IntentDescription("Opens SpoolDry with the current temperature, humidity and drying progress.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SpoolDryShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenDryerStatusIntent(),
            phrases: [
                "Show my filament dryer in \(.applicationName)",
                "Check filament drying in \(.applicationName)",
            ],
            shortTitle: "Dryer Status",
            systemImageName: "humidity"
        )
    }
}
