// Hardware abstraction for the ESP32-C6 build: SHT40 over I2C, heater NTC on ADC, fan tach,
// heater / fan / relay outputs, status LED and the BOOT button.
#pragma once
#include <Arduino.h>

#include "../core/DryerController.h"

namespace spooldry {

// Forces every power output to its safe (OFF) state. Called first thing in setup() and on any fault path.
void hardwareSafeState();

class Hardware {
public:
    void begin();
    // Non-blocking SHT40 sequencer; call every loop. Returns the latest decoded reading.
    const ClimateReading& pollClimate(uint32_t nowMs);
    NtcReading readHeaterNtc();
    uint16_t fanRpm(uint32_t nowMs);
    void apply(const ControllerOutputs& out);
    void showStatus(const Snapshot& s, bool identify, bool pairingOpen, uint32_t nowMs);

    enum class ButtonEvent : uint8_t { NONE, SHORT_PRESS, LONG_PRESS_3S, LONG_PRESS_10S };
    ButtonEvent pollButton(uint32_t nowMs);

    static ResetCause resetCause();
    static void deviceId(uint8_t out[6]);

private:
    bool shtPending_ = false;
    uint32_t shtTriggeredMs_ = 0;
    uint32_t shtLastMs_ = 0;
    uint8_t shtFailures_ = 0;
    ClimateReading climate_;
    uint32_t tachLastMs_ = 0;
    uint16_t rpm_ = 0;
    bool buttonDown_ = false;
    uint32_t buttonDownMs_ = 0;
    bool longFired3_ = false;
    bool longFired10_ = false;
    uint8_t lastDuty_ = 255;
};

}  // namespace spooldry
