# Testing

| Suite | Command | Result in this build environment |
|---|---|---|
| Firmware host tests (protocol, SHT40 CRC, NTC, state machine, 20 safety scenarios, fuzz) | `make -C esp32/test/host test` | ✅ 33 cases / 268 checks pass (ASan + UBSan, -Werror) |
| Firmware HAL type-check vs NimBLE 2.5.1 / Arduino 3.3 API | `esp32/test/compile_check/run.sh` | ✅ OK |
| Protocol constants in sync | `python3 tools/gen_protocol.py --check` | ✅ |
| Cross-language golden vectors | `make -C esp32/test/host golden` → used by `ProtocolGoldenTests.swift` | ✅ generated; Swift side runs on macOS |
| Localization (6 languages, specifiers) | `python3 tools/l10n/build_catalogs.py --check` | ✅ 327 keys |
| ASO limits | `python3 tools/aso_data.py` | ✅ |
| Swift syntax (44 files) | tree-sitter parse | ✅ 0 errors |
| SpoolDryKit unit tests (golden vectors, free tier 3rd/4th session, tracker, display state, filament DB, statistics, formatting) | `cd ios/Packages/SpoolDryKit && swift test` | ⏳ run on a Mac / CI (Swift toolchain not downloadable here) |
| App integration tests (3 free sessions → paywall, NACK not counted, demo free, records, disconnected, Live Activity state, 6 bundled languages) | Xcode ▸ Product ▸ Test | ⏳ run on a Mac / CI |
| Firmware ESP32 build | `cd esp32 && pio run` | ⏳ CI (toolchain hosts blocked here) |
| Website | build + Playwright: 9 pages, no console errors, no failed requests, no horizontal scroll at 390 px | ✅ |

Manual (hardware): pairing, Live Activity on Lock Screen/Dynamic Island, widget, app backgrounding/termination, phone
restart, ESP32 restart, reconnect, offline operation, purchase & restore in TestFlight sandbox. Bench safety test: see SAFETY.md.
