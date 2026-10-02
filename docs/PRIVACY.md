# Privacy

SpoolDry is offline-first and collects no personal data. Public policy: <https://tarikdavulcu.github.io/spooldry/privacy/>
(source: `website/src/build.py`, `PRIVACY`).

| Data | Where | Why | Leaves device? |
|---|---|---|---|
| Saved dryers (name, CoreBluetooth identifier, firmware) | SwiftData (app container) | reconnecting | No |
| Drying history (summary + 5-min chart series, pruned after 30/90/365 days) | SwiftData | history & statistics | No |
| Custom filament profiles, settings | SwiftData / UserDefaults | user content | No |
| Used free sessions counter | iOS Keychain, this device only | 3-session free tier | No |
| Latest dryer status | App Group UserDefaults | widgets & Live Activity | No |
| Purchase | Apple StoreKit | Lifetime entitlement | Apple only |

- Bluetooth: used only to talk directly to the user's SpoolDry dryer (`NSBluetoothAlwaysUsageDescription`, localized).
- No account, no server, no analytics/crash/ads SDK, no tracking (`NSPrivacyTracking = false`), no network calls by the app
  except Apple's StoreKit and links the user opens.
- App Store "App Privacy": **Data Not Collected**.
