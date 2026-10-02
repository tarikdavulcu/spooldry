// SpoolDry firmware configuration: board pin map and safety limits.
// Board: Espressif ESP32-C6-DevKitC-1-N8 (ESP32-C6-WROOM-1, 8 MB flash).
#pragma once
#include <stdint.h>

namespace spooldry {
namespace pins {
// I2C bus to the Sensirion SHT40 (Adafruit #4885, STEMMA QT). Arduino default SDA/SCL for ESP32-C6.
constexpr uint8_t kI2cSda = 23;
constexpr uint8_t kI2cScl = 22;
// Heater PWM: gate of the heater MOSFET (IRLB8721) through 100 R, 10 k pull-down to GND.
constexpr uint8_t kHeaterPwm = 18;
// Fan power: gate of the fan MOSFET (IRLB8721) through 100 R, 10 k pull-down to GND.
constexpr uint8_t kFanEnable = 19;
// Fan tachometer (San Ace open-collector pulse sensor, 2 pulses/rev), 10 k pull-up to 3V3.
constexpr uint8_t kFanTach = 20;
// Safety relay driver: gate of the relay-coil MOSFET (IRLB8721), 10 k pull-down. Coil is fed through
// the 85 C bimetal thermostat, so the relay drops out if the chamber overheats regardless of firmware.
constexpr uint8_t kHeaterRelay = 21;
// Heater-outlet NTC (Semitec 104GT-2, 100 k) to GND, 47 k 1% pull-up to 3V3. ADC1 channel 2.
constexpr uint8_t kHeaterNtcAdc = 2;
// On-board addressable RGB LED (WS2812 compatible) on the DevKitC-1.
constexpr uint8_t kStatusLed = 8;
// On-board BOOT button (active low). Short press = stop session, 3 s hold = reset fault.
constexpr uint8_t kLocalButton = 9;
}  // namespace pins

namespace limits {
// Chamber (SHT40) limits, degrees C.
constexpr float kAbsoluteChamberMaxC = 80.0f;     // immediate OVER_TEMPERATURE in any state
constexpr float kOverTargetMarginC = 8.0f;        // target + margin ...
constexpr uint32_t kOverTargetHoldMs = 30000;     // ... sustained this long -> OVER_TEMPERATURE
constexpr float kOverTempResetBelowC = 50.0f;     // RESET_SESSION accepted only below this
// Heater outlet (NTC) limits, degrees C.
constexpr float kHeaterDerateStartC = 110.0f;     // duty derated linearly from here ...
constexpr float kHeaterDerateZeroC = 120.0f;      // ... to zero here
constexpr float kHeaterAbsoluteMaxC = 140.0f;     // OVER_TEMPERATURE
constexpr float kHeaterResetBelowC = 60.0f;
// Plausibility.
constexpr float kChamberMinPlausibleC = -20.0f;
constexpr float kChamberMaxPlausibleC = 125.0f;
constexpr uint32_t kSensorFaultDebounceMs = 3000; // consecutive invalid time before latching
// Session timing.
constexpr float kPreheatBandC = 2.0f;             // within target - band -> DRYING
constexpr uint32_t kPreheatTimeoutMs = 90UL * 60UL * 1000UL; // heavy loads (2 spools) can take ~1 h
constexpr uint32_t kRunawayWindowMs = 10UL * 60UL * 1000UL;
constexpr float kRunawayMinRiseC = 2.0f;          // must rise this much per window while heating hard
constexpr float kRunawayMinAvgDuty = 50.0f;
constexpr float kDryingUnderTempC = 12.0f;        // in DRYING, below target - this ...
constexpr uint32_t kDryingUnderTempMs = 10UL * 60UL * 1000UL; // ... for this long -> HEATING_INEFFECTIVE
constexpr uint32_t kSessionSlackMs = 60UL * 60UL * 1000UL;    // hard cap = duration + slack
constexpr float kCooldownEndC = 45.0f;
constexpr uint32_t kCooldownMaxMs = 15UL * 60UL * 1000UL;
// Heater-stuck detection while the heater is commanded off.
constexpr uint32_t kStuckWindowMs = 5UL * 60UL * 1000UL;
constexpr float kStuckRiseC = 6.0f;
constexpr float kStuckMinTempC = 40.0f;
constexpr float kStuckOutletAboveChamberC = 25.0f;
constexpr uint32_t kStuckOutletHoldMs = 60000;
constexpr uint32_t kStuckResidualHeatMs = 180000;
// Fan.
constexpr uint32_t kFanSpinUpMs = 6000;
constexpr uint32_t kFanFaultHoldMs = 5000;
constexpr uint16_t kFanMinRpm = 1200;
constexpr float kFanAutoOnAboveC = 45.0f;
// Heater soft-start: maximum duty increase per second (limits PTC inrush on the 24 V supply).
constexpr float kDutySlewPerSec = 5.0f;
// Watchdog.
constexpr uint32_t kTaskWatchdogMs = 5000;
}  // namespace limits

namespace control {
constexpr float kKp = 14.0f;     // % duty per degree C
constexpr float kKi = 0.04f;     // % duty per degree C per second
constexpr float kIntegralMin = -20.0f;
constexpr float kIntegralMax = 70.0f;
constexpr uint32_t kTickMs = 250;
constexpr uint32_t kHeaterPwmHz = 1000;
}  // namespace control

namespace ntc {
constexpr float kSeriesOhms = 47000.0f;   // pull-up to 3V3 (keeps 20..150 C mid-scale)
constexpr float kR25Ohms = 100000.0f;     // Semitec 104GT-2
constexpr float kBeta = 4267.0f;          // B25/85 of 104GT-2
constexpr float kSupplyMv = 3300.0f;
constexpr float kOpenAboveMv = 3200.0f;
constexpr float kShortBelowMv = 15.0f;
// Cross-check: while heating, the outlet must not read far below the chamber.
constexpr float kImplausibleBelowChamberC = 10.0f;
constexpr uint32_t kImplausibleHoldMs = 60000;
}  // namespace ntc
}  // namespace spooldry
