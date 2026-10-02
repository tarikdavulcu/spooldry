# SpoolDry ESP32 Firmware 1.0.0

BLE filament-dryer controller for the **Espressif ESP32-C6-DevKitC-1-N8** (Arduino-ESP32 3.3.x, NimBLE-Arduino 2.5.x).
Setup & flashing: [../docs/ESP32_SETUP.md](../docs/ESP32_SETUP.md) · Protocol: [../docs/BLE_PROTOCOL.md](../docs/BLE_PROTOCOL.md) ·
Safety: [../docs/SAFETY.md](../docs/SAFETY.md) · Hardware: [../docs/HARDWARE.md](../docs/HARDWARE.md)

## Layout

```
esp32/
├── platformio.ini              PlatformIO (pioarduino) build, src_dir = SpoolDry
├── SpoolDry/                   Arduino sketch folder (open SpoolDry.ino in Arduino IDE)
│   ├── SpoolDry.ino            setup()/loop() glue: safe state, NVS, watchdog, tick scheduler
│   ├── partitions.csv          8 MB: nvs, otadata, 2× 3 MB OTA app, coredump, spiffs
│   └── src/
│       ├── core/               platform-independent, unit-tested on the host
│       │   ├── ProtocolConstants.h   GENERATED from protocol/spooldry-ble-v1.json
│       │   ├── Protocol.{h,cpp}      BLE v1 codec (commands, responses, characteristics)
│       │   ├── DryerController.*     state machine + safety supervisor + PI control
│       │   ├── Sensors.h             SHT4x frame/CRC decoding, NTC beta conversion
│       │   ├── Config.h              pin map, limits, control gains
│       │   └── Bytes.h               little-endian reader/writer
│       └── hal/
│           ├── Hardware.{h,cpp}      SHT40 over I²C, NTC ADC, tach ISR, LEDC heater PWM, relay, LED, button
│           └── BleLink.{h,cpp}       NimBLE GATT server, advertising, pairing window, command queue
└── test/
    ├── host/                   33 tests + thermal simulator + golden-vector generator (make test)
    └── compile_check/          type-checks the HAL against the NimBLE/Arduino API surface
```

## How it works

- **Loop:** every 250 ms the controller ingests the latest SHT40 reading (non-blocking, 1 Hz, high precision
  `0xFD`, CRC-8), the heater NTC (8-sample average) and the fan rpm (tach ISR, 2 pulses/rev), runs the safety
  supervisor, computes outputs and publishes the snapshot. The BLE callbacks only enqueue command frames.
- **BLE service:** 12 characteristics (see protocol doc). Device Status (36 B) is the atomic snapshot the app renders;
  individual characteristics (Temperature, Humidity, Heater, Fan, Session, Target, Remaining) exist for third-party tools.
  Notifications: 1 Hz and on every state change. Commands need an encrypted (bonded) link and are always answered by an ACK/NACK.
- **Temperature control:** PI (Kp 14 %/K, Ki 0.04 %/K·s, conditional-integration anti-windup) on the chamber
  temperature, time-averaged through 1 kHz PWM on Q1, soft-start ≤ 5 %/s, derated linearly by the heater-outlet
  NTC between 110 and 120 °C. The relay K1 is closed only in PREHEATING/DRYING.
- **Fan:** forced on whenever heating, cooling down, in OVER_TEMPERATURE, or while the chamber is ≥ 45 °C in AUTO.
- **State machine:** IDLE → PREHEATING → DRYING → COOLDOWN → COMPLETED (+ ERROR / OVER_TEMPERATURE). The drying timer
  starts only when the chamber is within 2 °C of target.
- **Safety:** see [SAFETY.md](../docs/SAFETY.md). Watchdog 5 s with panic reset; outputs default LOW; sessions never
  resume after reset; first fault is latched; over-temperature needs < 50 °C to reset.
- **Persistence (NVS):** session counter, last fault, device name.

## Configuration

Edit `SpoolDry/src/core/Config.h` (pins, limits, gains). Protocol constants are generated — change
`protocol/spooldry-ble-v1.json` and run `python3 tools/gen_protocol.py`.

## Tests

```bash
make -C test/host test   # g++ -Wall -Wextra -Werror -Wconversion, ASan + UBSan
```
