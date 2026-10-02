// SpoolDry drying state machine + safety supervisor + temperature control.
// Platform independent: all hardware access lives in the HAL (SpoolDry.ino / src/hal).
// The ESP32 is the safety authority. The phone is only a controller/monitor.
#pragma once
#include <stdint.h>

#include "Config.h"
#include "Protocol.h"
#include "Sensors.h"

namespace spooldry {

struct ControllerInputs {
    uint32_t nowMs = 0;
    ClimateReading chamber;  // latest SHT40 result
    NtcReading heater;       // latest heater-outlet NTC result
    uint16_t fanRpm = 0;
};

struct ControllerOutputs {
    bool relay = false;       // safety relay (second, independent heater switch)
    uint8_t heaterDuty = 0;   // 0..100 % PWM on the heater MOSFET
    bool fan = false;
    bool identify = false;    // blink the status LED
};

struct HardwareFeatures {
    bool heaterNtc = true;
    bool fanTach = true;
    bool safetyRelay = true;
};

class DryerController {
public:
    explicit DryerController(HardwareFeatures features = HardwareFeatures());

    void begin(uint32_t nowMs, ResetCause cause, uint32_t sessionCounter, ErrorCode lastFault);

    // Executes a decoded command. Always returns an ACK or NACK with the command's seq.
    Response handleCommand(const Command& cmd, uint32_t nowMs);
    // Builds a NACK for a frame that failed to decode.
    static Response nack(uint8_t seq, uint8_t opcode, ResultCode rc);

    // Physical button on the device.
    void localStop(uint32_t nowMs);
    bool localReset(uint32_t nowMs);

    // Runs one control/safety tick. Must be called every control::kTickMs.
    ControllerOutputs update(const ControllerInputs& in);

    const Snapshot& snapshot() const { return snap_; }
    uint16_t capabilities() const;
    uint32_t sessionCounter() const { return sessionCounter_; }
    ErrorCode lastLatchedFault() const { return lastLatchedFault_; }
    uint32_t unixTimeAt(uint32_t nowMs) const;
    bool timeSynced() const { return timeSynced_; }

    // Name changes requested over BLE are applied by the HAL (NVS + advertising).
    bool takePendingName(char* out, size_t cap);

    // Called by the HAL when a BLE client connects/disconnects (status flag only;
    // disconnect never stops a session - the device keeps itself safe autonomously).
    void setClientConnected(bool c) { clientConnected_ = c; }

private:
    struct Timer {
        bool active = false;
        uint32_t since = 0;
        void start(uint32_t now) { if (!active) { active = true; since = now; } }
        void restart(uint32_t now) { active = true; since = now; }
        void stop() { active = false; }
        bool elapsed(uint32_t now, uint32_t ms) const { return active && (now - since) >= ms; }
    };

    bool heating() const { return state_ == DeviceState::PREHEATING || state_ == DeviceState::DRYING; }
    bool sessionActive() const { return heating() || state_ == DeviceState::COOLDOWN; }
    void enterError(ErrorCode code, uint32_t now);
    void enterOverTemp(ErrorCode code, uint32_t now);
    void enterCooldown(EndReason reason, uint32_t now);
    void resetTrackers(uint32_t now);
    float computeDuty(float dtSec);
    bool computeFan() const;
    void refreshSnapshot(uint32_t now, const ControllerOutputs& out);
    Response ack(const Command& cmd) const;
    Response nackState(const Command& cmd, ResultCode rc) const;

    HardwareFeatures hw_;
    DeviceState state_ = DeviceState::IDLE;
    ErrorCode error_ = ErrorCode::NONE;
    ErrorCode lastLatchedFault_ = ErrorCode::NONE;
    EndReason endReason_ = EndReason::NONE;
    Material material_ = Material::CUSTOM;
    FanMode fanMode_ = FanMode::AUTO;
    float targetC_ = 50.0f;
    uint32_t durationSec_ = 4UL * 3600UL;
    uint32_t sessionCounter_ = 0;
    uint32_t sessionId_ = 0;
    uint32_t sessionStartMs_ = 0;
    uint32_t phaseStartMs_ = 0;
    uint32_t dryingStartMs_ = 0;
    uint32_t elapsedDryingMs_ = 0;
    uint32_t startUnix_ = 0;
    bool timeSynced_ = false;
    uint32_t unixAtSync_ = 0;
    uint32_t syncMs_ = 0;
    bool clientConnected_ = false;

    // Latest sensor values.
    bool chamberValid_ = false;
    float chamberC_ = 0.0f;
    float humidity_ = 0.0f;
    bool humidityValid_ = false;
    ErrorCode chamberFault_ = ErrorCode::NONE;
    bool heaterValid_ = false;
    float heaterC_ = 0.0f;
    ErrorCode heaterFault_ = ErrorCode::NONE;
    uint16_t fanRpm_ = 0;

    // Safety trackers.
    Timer chamberInvalid_;
    Timer heaterInvalid_;
    Timer overTarget_;
    bool overTargetArmed_ = false;  // armed once the chamber is below target + margin
    Timer underTemp_;
    Timer fanOn_;
    Timer fanLow_;
    Timer ntcImplausible_;
    Timer runawayWindow_;
    float runawayStartC_ = 0.0f;
    float runawayDutySum_ = 0.0f;
    uint32_t runawaySamples_ = 0;
    Timer stuckWindow_;
    Timer stuckOutlet_;
    uint32_t heatingEndedMs_ = 0;
    float stuckStartC_ = 0.0f;

    // Control.
    float integral_ = 0.0f;
    float duty_ = 0.0f;
    bool fanCommanded_ = false;
    uint32_t lastUpdateMs_ = 0;
    bool started_ = false;
    uint32_t identifyUntilMs_ = 0;
    bool identifyActive_ = false;

    char pendingName_[kMaxDeviceNameLen + 1] = {0};
    bool namePending_ = false;

    uint32_t bootMs_ = 0;
    uint16_t statusSeq_ = 0;
    Snapshot snap_;
};

}  // namespace spooldry
