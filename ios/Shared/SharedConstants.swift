import Foundation

/// Identifiers shared by the app and the widget extension. Must match the entitlements files.
enum SharedConstants {
    static let bundleID = "com.tarikdavulcu.spooldry"
    static let widgetBundleID = "com.tarikdavulcu.spooldry.widgets"
    static let appGroupID = "group.com.tarikdavulcu.spooldry"
    static let lifetimeProductID = "com.tarikdavulcu.spooldry.lifetime"
    static let widgetSnapshotKey = "widgetSnapshot.v1"
    static let widgetKind = "SpoolDryStatusWidget"
    static let urlScheme = "spooldry"
    static let websiteURL = URL(string: "https://tarikdavulcu.github.io/spooldry/")!
    static let supportURL = URL(string: "https://tarikdavulcu.github.io/spooldry/support/")!
    static let privacyURL = URL(string: "https://tarikdavulcu.github.io/spooldry/privacy/")!
    static let hardwareGuideURL = URL(string: "https://tarikdavulcu.github.io/spooldry/#build")!
}
