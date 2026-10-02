# ESP32 Setup & Firmware Flashing

Board: **Espressif ESP32-C6-DevKitC-1-N8** · Framework: **Arduino-ESP32 3.3.x** · Library: **NimBLE-Arduino 2.5.x**
Firmware: `esp32/` (PlatformIO project; the `SpoolDry/` folder is also a valid Arduino IDE sketch).

## 1. Required hardware
ESP32-C6-DevKitC-1-N8, USB-C **data** cable, SHT40 + STEMMA QT cable. For the full dryer see [HARDWARE.md](HARDWARE.md).
Unplug the 24 V supply while the board is connected to your computer.

## 2. Install Arduino IDE or PlatformIO
- Arduino IDE 2.x: <https://www.arduino.cc/en/software>
- or PlatformIO Core: `python3 -m pip install -U platformio`

## 3. Install ESP32 board support
Arduino IDE → Settings → *Additional boards manager URLs*:
```
https://espressif.github.io/arduino-esp32/package_esp32_index.json
```
Boards Manager → install **esp32 by Espressif Systems ≥ 3.3.12** (3.x is required for the ESP32-C6).
```bash
arduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
arduino-cli core install esp32:esp32 --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json
```
PlatformIO uses the pioarduino platform declared in `platformio.ini` (downloaded automatically).

## 4. Connect USB
Use the USB-C port labelled **UART** (Serial is routed there; `ARDUINO_USB_CDC_ON_BOOT=0`).

## 5. Select board
Arduino IDE: *Tools → Board → esp32 → ESP32C6 Dev Module*, **Flash Size: 8MB**, **Partition Scheme: Custom**
(`SpoolDry/partitions.csv` is picked up from the sketch folder). PlatformIO: `board = esp32-c6-devkitc-1`.

## 6. Select port
macOS `/dev/cu.usbserial-*` or `/dev/cu.wchusbserial-*`, Linux `/dev/ttyUSB0`/`ttyACM0`, Windows `COMx`.
```bash
arduino-cli board list
```

## 7. Install required libraries
```bash
arduino-cli lib install "NimBLE-Arduino@2.5.1"
```
(Arduino IDE: Library Manager → *NimBLE-Arduino* by h2zero.) PlatformIO installs it from `lib_deps`.
No other third-party libraries are used (the SHT40 driver with CRC is part of the firmware).

## 8. Compile firmware
```bash
cd esp32
pio run
# or
arduino-cli compile --fqbn esp32:esp32:esp32c6:FlashSize=8M,PartitionScheme=custom SpoolDry
```

## 9. Flash firmware
```bash
pio run -t upload
# or
arduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32c6:FlashSize=8M,PartitionScheme=custom SpoolDry
```
If upload fails: hold **BOOT**, tap **RESET**, release BOOT, retry.

## 10. Open Serial Monitor (115200 baud)
```
SpoolDry firmware 1.0.0 (BLE protocol v1) ready as "SpoolDry-A1B2"
Reset cause: 1, last fault: NONE, sessions so far: 0
Advertising SpoolDry service 5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44
```

## 11. Verify BLE advertising
With nRF Connect (iOS/Android) you should see `SpoolDry-XXXX` advertising service
`5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44`. Reading *Device Info* returns 23 bytes starting with `01 01`.

## 12. Open the SpoolDry iOS app
Device tab → **Add Dryer**. iOS asks for Bluetooth permission.

## 13. Connect device
Tap `SpoolDry-XXXX`. The app reads firmware/protocol/limits and saves the dryer. The first command triggers the iOS
pairing dialog; accept it. New phones can pair **within 5 minutes after power-on**, or hold **BOOT for 10 s** to
clear all bonds and reopen the pairing window.

## Local button & LED

| Action | Result |
|---|---|
| BOOT short press | stop the running session (→ COOLDOWN) |
| BOOT hold 3 s | reset a fault (only when safe) |
| BOOT hold 10 s | delete all BLE bonds, open pairing window 5 min |

LED: dim green idle · purple blink pairing window · orange preheating · amber drying · blue cooldown · green completed ·
red slow blink error · red fast blink over-temperature · white blink identify.

## Host tests (no hardware)
```bash
make -C esp32/test/host test      # 33 protocol + safety simulations (ASan/UBSan)
make -C esp32/test/host golden    # regenerate protocol/golden-vectors-v1.json
esp32/test/compile_check/run.sh   # type-check the Arduino glue against the library API surface
```

## OTA updates
Firmware 1.0 is updated over USB only. The 8 MB partition table already has two 3 MB OTA slots (`app0`/`app1`) and
`otadata`, so a later BLE OTA (planned: dedicated OTA characteristic, signed images, rollback via
`esp_ota_mark_app_valid_cancel_rollback()`) can be added without re-partitioning. The `OTA_BLE` capability bit stays 0
until that exists; the app shows "flash via USB" for now.
