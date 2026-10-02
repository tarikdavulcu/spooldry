# Product & Engineering Decisions

Every decision the brief left open was made autonomously; this is the record.

## Name & identifiers
- **Name: SpoolDry.** A web/App Store/trademark search (Oct 2026) found no app or mark named "SpoolDry" (similar but
  distinct: SpoolSmart, Spoolyard, PrintDry, PolyDryer). Not a legal clearance; run a formal check before trademarking.
- App Store name `SpoolDry: Filament Dryer`, bundle `com.tarikdavulcu.spooldry`, widget `com.tarikdavulcu.spooldry.widgets`,
  tests `com.tarikdavulcu.spooldry.tests`, App Group `group.com.tarikdavulcu.spooldry`,
  IAP `com.tarikdavulcu.spooldry.lifetime` (non-consumable, $19.99 US tier, price read from StoreKit at runtime).
- Website: `https://tarikdavulcu.github.io/spooldry/` (GitHub Pages, account `tarikdavulcu` exists). One variable
  (`SITE_URL`) switches to a custom domain such as `spooldry.tarikdavulcu.com`.

## Hardware
- **ESP32-C6-DevKitC-1-N8** over ESP32-C3 SuperMini (clone quality, antenna detuning, 4 MB) and ESP32-C3-DevKitM-1
  (micro-USB, out of stock at Adafruit). C6: official, USB-C, BLE 5, 8 MB → dual 3 MB OTA slots, Thread/Matter headroom.
  ESP32-S3 would also work but its dual core adds nothing here.
- **Arduino framework (Arduino-ESP32 3.3.x + NimBLE-Arduino 2.5.x)** over ESP-IDF: Arduino IDE flashing is the easiest
  path for makers, NimBLE is lighter and more reliable than Bluedroid, and the safety core is plain C++ that would port to
  IDF unchanged. PlatformIO (pioarduino) is provided for reproducible builds.
- **SHT40** over DHT11/22 (accuracy, speed, CRC) and AHT20 (high-RH accuracy). Own driver with CRC (no library).
- **24 V low-voltage architecture.** The user never wires mains; the certified Mean Well adapter is the only mains part.
- **PTC heater 24 V / 100 W**, self-limiting. **Chamber limit 70 °C**, set by the fan (industrial fans are rated
  −20…+70 °C) and consistent with consumer dryers. High-temp polymers (PEEK/PEI/PPS) are flagged as needing a different dryer.
- **San Ace 80 with tachometer** so a stalled fan is detected (the PTC still self-limits as a physical backup).
- **Defence in depth**: MOSFET + relay in series, 85 °C thermostat on the relay coil (the thermostat is rated 2 A so it
  switches the coil, not the heater), 100 °C one-shot TCO in the heater current, fuse, pull-downs, watchdog.

## Firmware behaviour
- The ESP32 is the safety authority; **BLE disconnect never stops a session** (would ruin long bakes, adds no safety).
- Drying timer starts at target − 2 °C. Preheat timeout 90 min (heavy loads), runaway check 2 °C/10 min at ≥ 50 % duty.
- After any reboot the device is IDLE; sessions are never resumed.
- Pairing: bonded LE Secure Connections; command writes require encryption; new bonds only within 5 min of power-on or
  after a 10 s BOOT press. Monitoring characteristics are readable without pairing.
- First fault wins (root cause preserved); over-temperature reset only below 50 °C.

## BLE protocol
Binary, little-endian, fixed-point (centi-units), single 36-byte atomic status snapshot plus the individual
characteristics the brief listed. Generated constants from one JSON spec + golden vectors guarantee firmware/app parity.

## iOS
- iOS 17+ (SwiftData, Observation, interactive widgets APIs), built with Xcode 26 / iOS 26 SDK (App Store requirement
  since April 2026). Swift 5 language mode to keep CoreBluetooth delegate code straightforward.
- MVVM with `@Observable` models: `BLEManager`/`DeviceLink` (transport), `SessionCoordinator` (business rules),
  `StoreManager` (StoreKit 2), SwiftUI views. Pure logic lives in the **SpoolDryKit** Swift package (unit-testable on
  macOS/Linux without UIKit/CoreBluetooth).
- **Free tier = 3 sessions**, counted exactly once per device-acknowledged START (idempotent by device ID + session ID),
  stored in the **Keychain** (survives reinstall, never leaves the device). Failed attempts, launches, days and restarts never count.
- Free also includes all features for those 3 bakes and one dryer; Lifetime unlocks unlimited sessions and multiple dryers.
- **Demo Dryer**: a simulated device speaking the real byte format, for App Review and curious users; never consumes sessions.
- Live Activity shows only device-reported data; no countdown during preheat; stale after 15 min without updates.
  Notifications only on received events (no guessed timers).
- History keeps summaries forever and a 5-minute chart series pruned after 30/90/365 days (user choice).
- Dark graphite design with teal accent; state is always text + icon (never color alone).
- Localization with String Catalogs: EN, DE, FR, ES, AR (RTL), JA — 327 keys, validated for format specifiers.

## Website
Static generator (Python) → HTML5 + Bootstrap 5.3.8 (self-hosted) + vanilla JS, dark default with light toggle,
glass/bento design, 6 localized landing pages with hreflang, JSON-LD (WebSite, SoftwareApplication, FAQPage), sitemap,
robots, manifest, OG/Twitter images. No cookies, no third-party requests. Product schema intentionally **not** used
(the hardware is not sold).

## Out of scope / not invented
- No fabricated purchase links: only links verified during research are used.
- Manufacturer drying values are summarised with source URLs; eSUN, SUNLU and FormFutura are not cited because no
  official drying page could be verified in this pass.
