# SpoolDry

iPhone/iPad app + ESP32-C6 firmware + open hardware for a Bluetooth filament dryer.

| | |
|---|---|
| App | SpoolDry: Filament Dryer · `com.tarikdavulcu.spooldry` · widgets `com.tarikdavulcu.spooldry.widgets` |
| IAP | `com.tarikdavulcu.spooldry.lifetime` (non-consumable, $19.99 US) · 3 free drying sessions |
| Firmware | 1.0.0 · ESP32-C6-DevKitC-1-N8 · BLE Protocol v1 (service `5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44`) |
| Website | `website/dist` → https://tarikdavulcu.github.io/spooldry/ (6 languages) |

```
ios/        Xcode 26 project (SpoolDry app, SpoolDryWidgets, tests) + SpoolDryKit package
esp32/      firmware (PlatformIO / Arduino IDE) + host tests
protocol/   BLE v1 JSON spec + golden vectors
website/    static site generator + assets
store/      App Store screenshots (6 langs × iPhone 6.9" + iPad 13") + fastlane metadata
design/     icon sources
docs/       PRODUCT_DECISIONS, HARDWARE, BLE_PROTOCOL, ESP32_SETUP, SAFETY, APP_STORE_CHECKLIST, ASO, PRIVACY, TESTING, FILAMENT_SOURCES
tools/      generators (protocol, l10n, screenshots, Xcode project)
```

Quick start: open `ios/SpoolDry.xcodeproj` in Xcode 26, set your Team, run on a device (Demo Dryer works without hardware).
Flash firmware: `cd esp32 && pio run -t upload`. Publish: see `docs/APP_STORE_CHECKLIST.md`.
