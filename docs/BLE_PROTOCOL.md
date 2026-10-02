# SpoolDry BLE Protocol v1

Single source of truth: [`protocol/spooldry-ble-v1.json`](../protocol/spooldry-ble-v1.json).
`tools/gen_protocol.py` generates `esp32/SpoolDry/src/core/ProtocolConstants.h` and
`ios/Packages/SpoolDryKit/Sources/SpoolDryKit/Protocol/ProtocolConstants.swift` from it, so firmware and app
share the **same UUIDs, opcodes, state values, error codes, units and versioning**.
Cross-language conformance is proven by `protocol/golden-vectors-v1.json` (bytes produced by the firmware codec,
decoded/encoded byte-exact by the iOS tests).

| Item | Value |
|---|---|
| Protocol version | `1` (byte 0 of Device Info, Device Status, every command and response) |
| Reference firmware | `1.0.0` |
| Byte order | little-endian |
| Advertised name | `SpoolDry-XXXX` (last 2 bytes of the BT MAC) or the user-set name (≤ 20 bytes) |
| Advertising | flags + complete 128-bit service UUID; name in scan response |
| Security | LE Secure Connections bonding, Just-Works. **Command writes require encryption.** New bonds accepted only for 5 min after power-on or after holding BOOT for 10 s. |
| MTU | firmware requests 185; iOS negotiates ≥ 185 automatically (Device Status needs ≥ 39) |
| Device ID | 6-byte BT MAC (`esp_read_mac(ESP_MAC_BT)`) |

## UUIDs

Base `5D0Fxxxx-2B7E-4C8A-9B1E-53504F4F4C44` (last group = ASCII "SPOOLD").

| UUID | Name | Props | Size | Payload |
|---|---|---|---|---|
| `5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44` | **SpoolDry Device Service** | – | – | – |
| `5D0F0002-…` | Device Info | read | 23 | see below |
| `5D0F0003-…` | Temperature | read, notify | 4 | `i16 chamber_cC, i16 heaterOutlet_cC` |
| `5D0F0004-…` | Humidity | read, notify | 2 | `u16 rh_cPct` |
| `5D0F0005-…` | Heater State | read, notify | 2 | `u8 flags (b0 relay, b1 output), u8 duty%` |
| `5D0F0006-…` | Fan State | read, notify | 4 | `u8 fanMode, u8 on, u16 rpm` |
| `5D0F0007-…` | Drying Session | read, notify | 20 | `u32 sessionId, u8 material, u8 endReason, i16 target_cC, u32 durationSec, u32 elapsedDryingSec, u32 startUnix` |
| `5D0F0008-…` | Target Temperature | read, notify | 2 | `i16 target_cC` |
| `5D0F0009-…` | Remaining Time | read, notify | 4 | `u32 seconds` (`0xFFFFFFFF` = unknown) |
| `5D0F000A-…` | **Device Status** | read, notify | 36 | full atomic snapshot (below) – the app renders this |
| `5D0F000B-…` | **Command** | write (encrypted) | ≤ 36 | command frame |
| `5D0F000C-…` | **Command Response** | read, notify | ≤ 16 | ACK/NACK frame |
| `5D0F000D-…` | Firmware Version | read | ≤ 16 | UTF-8 `"1.0.0"` |

Also exposed: standard Device Information Service `0x180A` (manufacturer, model, firmware, hardware revision).

### Units
`cC` = centi-degrees Celsius (`int16`, 4820 = 48.20 °C; `-32768` = invalid/no reading).
`cPct` = centi-percent RH (`uint16`, 1840 = 18.40 %; `65535` = invalid). Durations in seconds. Times are Unix seconds
(the device has no RTC; it learns the time from START_SESSION).

### Device Info (23 bytes)
| Off | Type | Field |
|---|---|---|
| 0 | u8 | protocolVersion (1) |
| 1 | u8 | hardwareRevision (1) |
| 2 | u8[6] | deviceId (BT MAC) |
| 8 | u8×3 | firmware major, minor, patch |
| 11 | i16 | minTarget_cC (3500) |
| 13 | i16 | maxTarget_cC (7000) |
| 15 | u32 | maxDurationSec (172800) |
| 19 | u16 | capabilities: b0 HEATER_NTC, b1 FAN_TACH, b2 SAFETY_RELAY, b3 IDENTIFY_LED, b4 LOCAL_BUTTON, b5 OTA_BLE (not set in 1.0) |
| 21 | u8 | resetReason: 0 unknown, 1 power-on, 2 software, 3 panic, 4 watchdog, 5 brownout, 6 other |
| 22 | u8 | lastFault (ErrorCode persisted in NVS) |

### Device Status (36 bytes)
| Off | Type | Field |
|---|---|---|
| 0 | u8 | protocolVersion |
| 1 | u8 | state |
| 2 | u8 | errorCode |
| 3 | u8 | flags: b0 HEATER_RELAY, b1 HEATER_OUTPUT, b2 FAN_ON, b3 CLIENT_CONNECTED, b4 CHAMBER_SENSOR_OK, b5 HEATER_SENSOR_OK, b6 SESSION_ACTIVE, b7 TIME_SYNCED |
| 4 | i16 | chamber_cC |
| 6 | u16 | humidity_cPct |
| 8 | i16 | heaterOutlet_cC |
| 10 | i16 | target_cC |
| 12 | u32 | remainingSec (PREHEATING: full duration, timer not running; DRYING: counting; COOLDOWN/COMPLETED: 0; else 0xFFFFFFFF) |
| 16 | u32 | elapsedDryingSec |
| 20 | u32 | sessionId (persistent counter; 0 after reboot until a new session) |
| 24 | u8 | material |
| 25 | u8 | heaterDuty % |
| 26 | u16 | fanRpm |
| 28 | u32 | uptimeSec |
| 32 | u8 | fanMode |
| 33 | u8 | endReason |
| 34 | u16 | statusSeq (increments every snapshot) |

Notifications: every 1 s while a client is subscribed, and immediately on every state change.

## State machine (shared enum)

| Value | State | Scope | Meaning |
|---|---|---|---|
| 0 | DISCONNECTED | app | no BLE link |
| 1 | CONNECTING | app | link / GATT discovery |
| 2 | CONNECTED | app | linked, waiting for first status |
| 3 | IDLE | device | heater off, ready |
| 4 | PREHEATING | device | heating; drying timer not started |
| 5 | DRYING | device | within 2 °C of target; timer counting |
| 6 | COOLDOWN | device | heater off, fan cooling to ≤ 45 °C (max 15 min) |
| 7 | COMPLETED | device | drying finished |
| 8 | ERROR | device | fault latched (first fault wins), heater off, relay open |
| 9 | OVER_TEMPERATURE | device | over-temperature latched, heater off, fan forced on |

```
IDLE --START(ACK)--> PREHEATING --chamber >= target-2--> DRYING --elapsed >= duration--> COOLDOWN --> COMPLETED
PREHEATING/DRYING --STOP or BOOT button--> COOLDOWN --> IDLE
any heating state --fault--> ERROR          any state --over-temp--> OVER_TEMPERATURE
ERROR/OVER_TEMPERATURE/COMPLETED --RESET_SESSION (when safe)--> IDLE
reboot (any cause) --> IDLE  (sessions are never resumed)
```

## Commands

Frame: `[u8 version=1][u8 opcode][u8 seq][u8 len][payload…]`, `len ≤ 32`, total length must equal `4+len`.

| Op | Name | Payload | Rules |
|---|---|---|---|
| 1 | START_SESSION | `u8 material, i16 target_cC, u32 durationSec, u32 unixTime, u8 fanMode` (12) | target 35–70 °C, duration 900 s–48 h; NACK BUSY if a session runs, NOT_ALLOWED_IN_STATE in ERROR/OVER_TEMP, SENSOR_FAULT if sensors invalid |
| 2 | STOP_SESSION | – | idempotent; heating → COOLDOWN (endReason STOPPED_BY_USER) |
| 3 | SET_TARGET_TEMP | `i16 target_cC` | not in ERROR/OVER_TEMP |
| 4 | SET_DURATION | `u32 durationSec` | in DRYING a shorter value completes immediately |
| 5 | SET_FILAMENT | `u8 material` | label only |
| 6 | SET_FAN_MODE | `u8 mode` (0 AUTO, 1 ON, 2 OFF) | OFF refused while heating/cooling/fault (fan is mandatory) |
| 7 | REQUEST_STATUS | – | ACK + status notification |
| 8 | RESET_SESSION | – | clears COMPLETED/ERROR/OVER_TEMP; OVER_TEMP only below 50 °C chamber and 60 °C heater; ERROR only with valid sensors |
| 9 | IDENTIFY | – | blinks the status LED 5 s |
| 10 | SET_DEVICE_NAME | UTF-8, 1–20 bytes, no control chars | stored in NVS, re-advertised |

## Responses

Frame: `[u8 version][u8 type: 0x80 ACK / 0x81 NACK][u8 seq][u8 opcode][u8 result][u8 len][payload ≤ 10]`.
The app matches responses by `seq`, times out after 5 s and **never assumes success**.

START_SESSION ACK payload: `u32 sessionId, u32 deviceUnixTime`. A free session is counted only at this ACK.
NACK payload (state rejections): `u8 state, u8 errorCode`.

| Result | Name |
|---|---|
| 0 | OK |
| 1 | UNKNOWN_OPCODE |
| 2 | BAD_LENGTH |
| 3 | UNSUPPORTED_VERSION |
| 4 | INVALID_PARAMETER |
| 5 | BUSY |
| 6 | NOT_ALLOWED_IN_STATE |
| 7 | SENSOR_FAULT |
| 8 | OVER_TEMPERATURE_LOCK |
| 9 | INTERNAL_ERROR |

## Error codes

| Code | Name | Trigger |
|---|---|---|
| 0 | NONE | |
| 1 | SENSOR_I2C | SHT40 not answering for 3 s |
| 2 | SENSOR_CRC | CRC-8 mismatch for 3 s |
| 3 | SENSOR_RANGE | implausible value (< −20 or > 125 °C, stuck bus pattern) |
| 4 | NTC_OPEN | outlet NTC open, or reads > 10 °C below chamber while heating for 60 s (detached) |
| 5 | NTC_SHORT | outlet NTC shorted |
| 6 | OVER_TEMP_CHAMBER | chamber ≥ 80 °C (any state) or ≥ target + 8 °C for 30 s |
| 7 | OVER_TEMP_HEATER | heater outlet ≥ 140 °C |
| 8 | PREHEAT_TIMEOUT | target not reached in 90 min |
| 9 | HEATING_INEFFECTIVE | < 2 °C rise in 10 min at ≥ 50 % duty, or > 12 °C below target for 10 min while drying |
| 10 | HEATER_STUCK_ON | heat while heater commanded off (chamber +6 °C in 5 min above 40 °C, or outlet ≥ chamber + 25 °C for 60 s) |
| 11 | FAN_FAILURE | tach < 1200 rpm for 5 s after 6 s spin-up |
| 12 | SESSION_TIME_LIMIT | session longer than duration + 90 min preheat + 60 min |
| 13 | UNEXPECTED_RESET | last reset was panic/watchdog/brownout (informational) |
| 14 | INTERNAL | |

## Enums

Materials: 0 CUSTOM, 1 PLA, 2 PETG, 3 ABS, 4 ASA, 5 TPU, 6 PA, 7 PC, 8 PVA, 9 BVOH, 10 PEEK, 11 PEI, 12 PPS,
13 PA_CF, 14 PA_GF, 15 PETG_CF, 16 PLA_CF, 17 PC_CF, 18 ASA_CF, 19 PPS_CF.
End reasons: 0 NONE, 1 COMPLETED, 2 STOPPED_BY_USER, 3 STOPPED_ON_DEVICE, 4 ERROR, 5 OVER_TEMPERATURE.

## Versioning rules (forward compatibility)

1. Fields are only ever **appended**; decoders accept longer payloads and ignore unknown trailing bytes.
2. New opcodes/enum values may be added in v1.x; unknown enum values decode to safe defaults on iOS.
3. A breaking change bumps `protocolVersion`. The firmware NACKs other versions with `UNSUPPORTED_VERSION`;
   the app reads Device Info first and asks the user to update when `protocolVersion != 1`.
4. Capability bits announce optional hardware (NTC, tach, relay, OTA) so the app adapts per device.

## Disconnect behaviour

The ESP32 is the safety authority. A BLE disconnect **does not stop** a session: the firmware continues with all
limits and the hard time cap. The phone is a controller/monitor; it re-arms a pending connection and resynchronises
history, widgets and the Live Activity on reconnect. Rationale: stopping on disconnect would abort long nylon bakes when
the phone leaves the room, while adding no safety (every limit is enforced on the device and in hardware).
