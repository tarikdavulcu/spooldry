import Foundation
import Security
import SpoolDryKit

/// Stores the number of consumed free drying sessions in the iOS Keychain (on this device only).
/// The Keychain survives app reinstalls, so the 3-session limit is not reset by deleting the app.
/// No server is involved; the value never leaves the device.
final class KeychainUsageCounterStore: UsageCounterStore {
    private let service = "com.tarikdavulcu.spooldry.usage"
    private let account = "freeDryingSessionsUsed"

    func load() -> Int {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let text = String(data: data, encoding: .utf8), let value = Int(text) else {
            return 0
        }
        return max(0, value)
    }

    func save(_ value: Int) {
        let data = Data(String(max(0, value)).utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
