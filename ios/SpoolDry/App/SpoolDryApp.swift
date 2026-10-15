import SwiftData
import SwiftUI

@main
struct SpoolDryApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .modelContainer(model.container)
                .task { await model.bootstrap() }
                .onOpenURL { url in
                    // spooldry://dashboard (widgets, Live Activities)
                    if url.scheme == SharedConstants.urlScheme { model.selectedTab = .dashboard }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.storage.appBecameActive() }
                    if phase == .background { model.storage.scanner.stop() }
                }
        }
    }
}
