#include "Hardware.h"

#include <Wire.h>

#include "esp_mac.h"
#include "esp_system.h"

namespace spooldry {

static volatile uint32_t g_tachPulses = 0;
static bool g_heaterPwmAttached = false;

static void IRAM_ATTR onTachPulse() { g_tachPulses = g_tachPulses + 1; }

void hardwareSafeState() {
    // Heater, relay and fan gates also have 10 k pull-downs, so they are OFF while the pins float
    // during reset/boot. This makes the default explicit as early as possible in software too.
    if (g_heaterPwmAttached) {
        ledcWrite(pins::kHeaterPwm, 0);
    } else {
        pinMode(pins::kHeaterPwm, OUTPUT);
        digitalWrite(pins::kHeaterPwm, LOW);
    }
    pinMode(pins::kHeaterRelay, OUTPUT);
    digitalWrite(pins::kHeaterRelay, LOW);
    pinMode(pins::kFanEnable, OUTPUT);
    digitalWrite(pins::kFanEnable, LOW);
}

void Hardware::begin() {
    hardwareSafeState();
    g_heaterPwmAttached = ledcAttach(pins::kHeaterPwm, control::kHeaterPwmHz, 10);
    if (g_heaterPwmAttached) ledcWrite(pins::kHeaterPwm, 0);

    pinMode(pins::kFanTach, INPUT_PULLUP);  // external 10 k pull-up to 3V3 is the primary pull-up
    attachInterrupt(digitalPinToInterrupt(pins::kFanTach), onTachPulse, FALLING);

    pinMode(pins::kLocalButton, INPUT_PULLUP);
    analogSetPinAttenuation(pins::kHeaterNtcAdc, ADC_11db);

    Wire.begin(pins::kI2cSda, pins::kI2cScl, 100000);
    Wire.setTimeOut(25);
    Wire.beginTransmission(kSht4xAddress);
    Wire.write(kSht4xSoftReset);
    Wire.endTransmission();
    delay(2);
    climate_.valid = false;
    climate_.fault = ErrorCode::SENSOR_I2C;
    tachLastMs_ = millis();
}

const ClimateReading& Hardware::pollClimate(uint32_t nowMs) {
    if (!shtPending_ && (nowMs - shtLastMs_) >= 1000) {
        Wire.beginTransmission(kSht4xAddress);
        Wire.write(kSht4xMeasureHighPrecision);
        if (Wire.endTransmission() == 0) {
            shtPending_ = true;
            shtTriggeredMs_ = nowMs;
        } else {
            climate_ = ClimateReading();
            climate_.fault = ErrorCode::SENSOR_I2C;
            shtFailures_++;
        }
        shtLastMs_ = nowMs;
    }
    if (shtPending_ && (nowMs - shtTriggeredMs_) >= 12) {  // datasheet max 8.3 ms
        shtPending_ = false;
        uint8_t frame[6] = {0};
        size_t n = 0;
        if (Wire.requestFrom(static_cast<uint8_t>(kSht4xAddress), static_cast<uint8_t>(6)) == 6) {
            while (Wire.available() && n < 6) frame[n++] = static_cast<uint8_t>(Wire.read());
        }
        climate_ = decodeSht4x(frame, n);
        if (climate_.valid) {
            shtFailures_ = 0;
        } else {
            shtFailures_++;
        }
    }
    if (shtFailures_ >= 3) {
        // Bus recovery: re-initialise the peripheral and soft-reset the sensor.
        Wire.end();
        Wire.begin(pins::kI2cSda, pins::kI2cScl, 100000);
        Wire.setTimeOut(25);
        Wire.beginTransmission(kSht4xAddress);
        Wire.write(kSht4xSoftReset);
        Wire.endTransmission();
        shtFailures_ = 0;
        shtPending_ = false;
    }
    return climate_;
}

NtcReading Hardware::readHeaterNtc() {
    uint32_t sum = 0;
    for (int i = 0; i < 8; ++i) sum += analogReadMilliVolts(pins::kHeaterNtcAdc);
    return ntcFromMillivolts(static_cast<float>(sum) / 8.0f);
}

uint16_t Hardware::fanRpm(uint32_t nowMs) {
    const uint32_t dt = nowMs - tachLastMs_;
    if (dt >= 1000) {
        noInterrupts();
        const uint32_t pulses = g_tachPulses;
        g_tachPulses = 0;
        interrupts();
        // San Ace pulse sensor: 2 pulses per revolution.
        const uint32_t rpm = pulses * 60000UL / (2UL * dt);
        rpm_ = rpm > 65535UL ? 65535 : static_cast<uint16_t>(rpm);
        tachLastMs_ = nowMs;
    }
    return rpm_;
}

void Hardware::apply(const ControllerOutputs& out) {
    // Order matters when switching off: PWM first, then relay; when switching on: relay first.
    if (!out.relay || out.heaterDuty == 0) {
        if (g_heaterPwmAttached) ledcWrite(pins::kHeaterPwm, 0);
        else digitalWrite(pins::kHeaterPwm, LOW);
    }
    digitalWrite(pins::kHeaterRelay, out.relay ? HIGH : LOW);
    if (out.relay && out.heaterDuty > 0) {
        if (out.heaterDuty != lastDuty_) {
            const uint32_t duty = (static_cast<uint32_t>(out.heaterDuty) * 1023UL) / 100UL;
            if (g_heaterPwmAttached) ledcWrite(pins::kHeaterPwm, duty);
        }
    }
    lastDuty_ = (out.relay && out.heaterDuty > 0) ? out.heaterDuty : 0;
    digitalWrite(pins::kFanEnable, out.fan ? HIGH : LOW);
}

void Hardware::showStatus(const Snapshot& s, bool identify, bool pairingOpen, uint32_t nowMs) {
    const bool blinkSlow = (nowMs / 500) % 2 == 0;
    const bool blinkFast = (nowMs / 150) % 2 == 0;
    uint8_t r = 0, g = 0, b = 0;
    if (identify) {
        if (blinkFast) r = g = b = 80;
    } else {
        switch (s.state) {
            case DeviceState::PREHEATING: r = 80; g = 30; break;
            case DeviceState::DRYING: r = 60; g = 40; break;
            case DeviceState::COOLDOWN: b = 60; break;
            case DeviceState::COMPLETED: g = 70; break;
            case DeviceState::ERROR: if (blinkSlow) r = 90; break;
            case DeviceState::OVER_TEMPERATURE: if (blinkFast) r = 120; break;
            default:
                if (pairingOpen && (nowMs / 1000) % 2 == 0) { r = 40; b = 60; }
                else g = 8;
                break;
        }
    }
    rgbLedWrite(pins::kStatusLed, r, g, b);
}

Hardware::ButtonEvent Hardware::pollButton(uint32_t nowMs) {
    const bool down = digitalRead(pins::kLocalButton) == LOW;
    ButtonEvent ev = ButtonEvent::NONE;
    if (down && !buttonDown_) {
        buttonDown_ = true;
        buttonDownMs_ = nowMs;
        longFired3_ = longFired10_ = false;
    } else if (down && buttonDown_) {
        const uint32_t held = nowMs - buttonDownMs_;
        if (held >= 10000 && !longFired10_) {
            longFired10_ = true;
            ev = ButtonEvent::LONG_PRESS_10S;
        } else if (held >= 3000 && !longFired3_) {
            longFired3_ = true;
            ev = ButtonEvent::LONG_PRESS_3S;
        }
    } else if (!down && buttonDown_) {
        buttonDown_ = false;
        const uint32_t held = nowMs - buttonDownMs_;
        if (held >= 50 && held < 3000) ev = ButtonEvent::SHORT_PRESS;
    }
    return ev;
}

ResetCause Hardware::resetCause() {
    switch (esp_reset_reason()) {
        case ESP_RST_POWERON: return ResetCause::POWER_ON;
        case ESP_RST_SW: return ResetCause::SOFTWARE;
        case ESP_RST_PANIC: return ResetCause::PANIC;
        case ESP_RST_INT_WDT:
        case ESP_RST_TASK_WDT:
        case ESP_RST_WDT: return ResetCause::WATCHDOG;
        case ESP_RST_BROWNOUT: return ResetCause::BROWNOUT;
        case ESP_RST_UNKNOWN: return ResetCause::UNKNOWN;
        default: return ResetCause::OTHER;
    }
}

void Hardware::deviceId(uint8_t out[6]) {
    if (esp_read_mac(out, ESP_MAC_BT) != ESP_OK) {
        for (int i = 0; i < 6; ++i) out[i] = 0;
    }
}

}  // namespace spooldry
