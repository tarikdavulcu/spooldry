# SpoolDry Safety

> **SpoolDry hardware is a hobby / prototyping project. It is not certified (no CE, UKCA, UL, PSE or similar).**
> You build and operate it at your own risk. Do not leave an experimental prototype unattended.

## Rules

- Never bypass the thermal fuse (TCO) or the thermostat.
- Never operate damaged wiring, cracked connectors or a heater with exposed live parts.
- Use the specified certified 24 V supply (Mean Well GST220A24). Do not open it. No user mains wiring.
- Do not exceed heater (100 W), wire (18 AWG heater loop), connector (7.5 A) and fuse ratings.
- Keep flammable materials away from exposed heating elements; never print the heater duct in PLA/PETG.
- Use a proper, heat-rated enclosure; keep the electronics box outside the hot zone.
- Use independent thermal protection in addition to the firmware (thermostat + TCO are mandatory, not optional).
- Do not leave an experimental prototype unattended. Use a smoke detector in the room.

## Protection layers (defence in depth)

| # | Layer | Type | Acts on | Independent of firmware? |
|---|---|---|---|---|
| 1 | Firmware limits: absolute 80 °C chamber, target + 8 °C for 30 s, heater-outlet derating 110→120 °C and cut-off 140 °C | software | MOSFET + relay | no |
| 2 | Sensor validation: SHT40 CRC-8, plausibility, 3 s debounce; NTC open/short and cross-check vs chamber | software | heater off | no |
| 3 | Fan monitoring via tachometer (< 1200 rpm for 5 s) | software | heater off | no |
| 4 | Thermal-runaway & preheat timeout, heater-stuck detection, absolute session time cap | software | heater off / fault | no |
| 5 | Task watchdog (5 s, panic → reset). On reset all GPIOs float → 10 kΩ pull-downs keep every load OFF; sessions never resume | hardware + software | all loads | partly |
| 6 | Heater defaults OFF: pull-downs on Q1/Q2/Q3 gates, outputs driven LOW first in `setup()` | hardware | all loads | **yes** |
| 7 | Two switches in series in the heater path: MOSFET Q1 and relay K1 (separate GPIOs) | hardware | heater | partly |
| 8 | 85 °C NC bimetal thermostat feeding the relay coil: drops K1 on chamber over-temperature | hardware | heater | **yes** |
| 9 | 100 °C one-shot thermal cutoff in the heater current (covers shorted MOSFET + welded relay) | hardware | heater | **yes** |
| 10 | PTC self-regulation: power collapses without airflow | physics | heater | **yes** |
| 11 | 7.5 A fuse on +24 V; certified PSU with its own OCP/OVP/OTP | hardware | everything | **yes** |

The phone is never part of the safety chain. BLE disconnects, app crashes or phone restarts do not affect the dryer.

## Startup safe state

`hardwareSafeState()` is the first call in `setup()`; before that the gate pull-downs hold all MOSFETs off. After any
reset the controller starts in `IDLE`, reports the reset cause in Device Info, and reports `UNEXPECTED_RESET` after a
panic/watchdog/brownout. A running session is **never** resumed.

## Firmware fault matrix (all verified by host tests, see `docs/TESTING.md`)

| Fault | Detection | Reaction | Test |
|---|---|---|---|
| Sensor disconnected | I²C NACK ≥ 3 s | ERROR `SENSOR_I2C`, heater off, fan on | `sensor_disconnected_latches_error_within_debounce` |
| Corrupted sensor data | CRC mismatch ≥ 3 s | ERROR `SENSOR_CRC` | `sensor_crc_errors_latch_sensor_crc` |
| Invalid temperature / humidity | outside −20…125 °C, stuck pattern | value rejected, ERROR `SENSOR_RANGE` | `invalid_temperature_reading_is_rejected` |
| Over-temperature | ≥ 80 °C any state / target + 8 °C 30 s | OVER_TEMPERATURE latched, reset only < 50 °C | `over_temperature_when_heater_stuck_on_during_session`, `absolute_chamber_limit_trips_in_any_state` |
| Heater stuck on | heat rise with heater off | ERROR `HEATER_STUCK_ON`, relay open | `heater_stuck_detected_while_idle` |
| Fan failure | tach < 1200 rpm | ERROR `FAN_FAILURE`, heater off | `fan_failure_stops_heater` |
| Fan failure without tach | NTC derating | outlet stays < 140 °C | `fan_failure_without_tach_is_contained_by_ntc_derating` |
| Heater/sensor detached | runaway window, NTC plausibility | `HEATING_INEFFECTIVE` / `NTC_OPEN` | `heating_ineffective_when_heater_disconnected`, `ntc_detached_is_caught_by_plausibility` |
| BLE disconnect | – | session continues safely | `ble_disconnect_does_not_stop_session` |
| Watchdog / unexpected reboot | reset reason | IDLE, outputs off, `UNEXPECTED_RESET` | `reboot_never_resumes_and_reports_unexpected_reset` |
| Random command/fault sequences | invariant checks every tick | heater never on outside PREHEATING/DRYING, fan always on while heating | `fuzz_random_commands_and_faults_never_violate_invariants` |

## Bench test before first unattended-free use

1. Power up without heater connected: LED dim green, serial log shows `ready`.
2. Disconnect the SHT40 → START must be rejected (`SENSOR_FAULT`).
3. Start a 15 min PLA session with the lid open: fan runs, relay clicks, duty ramps up.
4. Hold the fan blades → within ~11 s `FAN_FAILURE`, relay opens.
5. Warm the thermostat with a hot-air tool (≥ 85 °C) during heating → relay drops although firmware says heating.
6. Measure that heater current is 0 A in IDLE with a clamp meter.
