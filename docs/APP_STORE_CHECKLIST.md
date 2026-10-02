# App Store Checklist

Status legend: ✅ done in repo · 👤 needs your Apple account / action

## Before building
- 👤 Apple Developer Program membership active; Paid Apps agreement, tax and banking completed (needed for the IAP).
- 👤 Set `DEVELOPMENT_TEAM` (Xcode → SpoolDry & SpoolDryWidgets targets → Signing). Automatic signing creates:
  - App ID `com.tarikdavulcu.spooldry` (capabilities: App Groups, Time Sensitive Notifications; Background Modes is Info.plist only)
  - App ID `com.tarikdavulcu.spooldry.widgets` (App Groups)
  - App Group `group.com.tarikdavulcu.spooldry`
- ✅ Xcode 26 / iOS 26 SDK project, deployment target iOS 17.0, iPhone + iPad.
- ✅ Privacy manifests (app + widget): no tracking, no collected data, UserDefaults reasons CA92.1 / 1C8F.1.
- ✅ `ITSAppUsesNonExemptEncryption = NO` (only Apple-provided BLE encryption / HTTPS by the OS).

## App Store Connect – app record (👤)
| Field | Value |
|---|---|
| Name | SpoolDry: Filament Dryer |
| Bundle ID | com.tarikdavulcu.spooldry |
| SKU | SPOOLDRY-IOS-001 |
| Primary language | English (U.S.) |
| Primary category | Utilities · Secondary: Productivity |
| Price | Free (with in-app purchase) |
| Support URL | https://tarikdavulcu.github.io/spooldry/support/ |
| Marketing URL | https://tarikdavulcu.github.io/spooldry/ |
| Privacy Policy URL | https://tarikdavulcu.github.io/spooldry/privacy/ |
| Copyright | 2026 Tarık Davulcu |

Localizations (✅ text ready in `store/fastlane/metadata/`): en-US, de-DE, fr-FR, es-ES, ar-SA, ja.

## In-App Purchase (👤 create, ✅ values ready)
| Field | Value |
|---|---|
| Type | Non-Consumable |
| Reference name | SpoolDry Lifetime |
| Product ID | com.tarikdavulcu.spooldry.lifetime |
| Price | USD 19.99 (let Apple equalize other storefronts) |
| Family Sharing | Off (can be enabled later; cannot be disabled once on) |
| Display name / description | see `ios/SpoolDry/Resources/SpoolDry.storekit` (6 languages) |
| Review screenshot | paywall screenshot `store/screenshots/en-US/iphone69-8-lifetime.png` |

## App Privacy questionnaire (👤 answer)
- Data collection: **No, we do not collect data from this app.** (All data stays on device; no analytics/ads/SDKs.)

## Age rating (👤 answer the 2026 questionnaire)
All "None"/"No" → expected rating **4+**. No user-generated content, no web browsing, no gambling, no medical claims.

## Screenshots (✅ generated)
- iPhone 6.9" 1320×2868 × 8 per locale, iPad 13" 2064×2752 × 8 per locale in `store/screenshots/<locale>/`.
- Optional: replace with Simulator captures using the Demo Dryer.

## App Review notes (✅ `store/fastlane/metadata/review_information/notes.txt`)
Hardware-dependent app: explain the Demo Dryer path and the IAP location. Optionally attach a short video of the real dryer.

## Upload (👤)
```bash
cd ios && xcodebuild -scheme SpoolDry -configuration Release -archivePath build/SpoolDry.xcarchive archive
# then Xcode Organizer → Distribute App → App Store Connect, or:
cd store/fastlane && fastlane deliver   # metadata + screenshots (needs App Store Connect API key or Apple ID login + 2FA)
```

## Final checks
- ✅ Bluetooth permission string (6 languages via InfoPlist.xcstrings)
- ✅ Restore Purchases visible on paywall and in Settings
- ✅ Terms of Use (Apple standard EULA) and Privacy Policy links on paywall
- 👤 TestFlight run on a physical iPhone with real hardware: pairing, Live Activity on Lock Screen, Dynamic Island, widget.
