import SwiftData
import SwiftUI

@main
struct SpoolDryApp: App {
    @State private var model = AppModel()

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
        }
    }
}
