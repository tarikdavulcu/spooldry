// Lumped thermal model of a SpoolDry chamber used to exercise the real controller code on the host.
// It is deliberately simple; it exists to drive the state machine and safety logic through
// realistic trajectories, not to predict exact temperatures of a specific build.
#pragma once
#include <cmath>
#include <cstdint>

#include "../../SpoolDry/src/core/DryerController.h"
#include "../../SpoolDry/src/core/Sensors.h"
#include "../../SpoolDry/src/core/Bytes.h"

namespace sim {

using namespace spooldry;

struct Faults {
    bool sensorDisconnected = false;  // I2C NACK -> SENSOR_I2C
    bool sensorCrc = false;           // corrupted frames
    bool sensorStuckHot = false;      // reports 150 C (out of plausible range)
    bool ntcOpen = false;
    bool ntcDetachedReadsAmbient = false;  // NTC fell off the duct and reads room temperature
    bool fanBroken = false;           // fan does not spin (tach reads 0)
    bool heaterDisconnected = false;  // no heat produced
    bool heaterStuckOn = false;       // MOSFET shorted AND relay welded (worst case, firmware must flag)
    float heaterPowerScale = 1.0f;    // weak heater
};

struct Plant {
    float ambientC = 22.0f;
    float chamberC = 22.0f;
    float heaterOutletC = 22.0f;
    float moisture = 1.0f;   // relative moisture content of filament + air (1 = equilibrium with room)
    float ambientRh = 55.0f;
    float heatCapacityJPerK = 3000.0f;
    float lossWPerK = 1.2f;
    float maxPowerW = 100.0f;
    Faults faults;

    static float psat(float tC) { return 6.112f * std::exp(17.62f * tC / (243.12f + tC)); }

    float humidityRh() const {
        // Absolute humidity follows moisture released by filament; relative humidity falls as air warms.
        float rh = ambientRh * moisture * psat(ambientC) / psat(chamberC);
        if (rh > 100.0f) rh = 100.0f;
        if (rh < 0.5f) rh = 0.5f;
        return rh;
    }

    // Advances the model by dt seconds with the controller outputs applied.
    void step(const ControllerOutputs& out, float dt) {
        float duty = out.relay ? out.heaterDuty / 100.0f : 0.0f;
        if (faults.heaterStuckOn) duty = 1.0f;
        if (faults.heaterDisconnected) duty = 0.0f;
        const bool airflow = out.fan && !faults.fanBroken;
        // PTC self-regulation: without airflow the element throttles to ~15 % of rated power.
        const float power = duty * maxPowerW * faults.heaterPowerScale * (airflow ? 1.0f : 0.15f);
        const float loss = lossWPerK * (chamberC - ambientC);
        chamberC += (power - loss) / heatCapacityJPerK * dt;
        // Heater outlet: small rise with airflow, large rise in still air (first-order lag).
        const float outletTarget = chamberC + (airflow ? power / 38.0f : power * 4.0f);
        heaterOutletC += (outletTarget - heaterOutletC) * std::fmin(1.0f, dt / 20.0f);
        // Moisture is driven out faster at higher temperature, slowly re-absorbed from room air when cold.
        const float driveOut = chamberC > 35.0f ? 0.00004f * (chamberC - 35.0f) : 0.0f;
        moisture += (-driveOut * moisture + 0.000002f * (1.0f - moisture)) * dt;
        if (moisture < 0.05f) moisture = 0.05f;
    }

    // Produces the inputs the HAL would deliver.
    ControllerInputs read(uint32_t nowMs, bool fanOn) const {
        ControllerInputs in;
        in.nowMs = nowMs;
        if (faults.sensorDisconnected) {
            in.chamber.valid = false;
            in.chamber.fault = ErrorCode::SENSOR_I2C;
        } else {
            const float t = faults.sensorStuckHot ? 150.0f : chamberC;
            uint8_t frame[6];
            encodeFrame(t, humidityRh(), frame);
            if (faults.sensorCrc) frame[2] ^= 0x5A;
            in.chamber = decodeSht4x(frame, 6);
        }
        if (faults.ntcOpen) {
            in.heater = ntcFromMillivolts(3299.0f);
        } else {
            const float t = faults.ntcDetachedReadsAmbient ? ambientC : heaterOutletC;
            in.heater = ntcFromMillivolts(ntcMillivoltsForTemp(t));
        }
        in.fanRpm = (fanOn && !faults.fanBroken) ? 6800 : 0;
        return in;
    }

    static void encodeFrame(float tC, float rh, uint8_t* f) {
        float tr = (tC + 45.0f) * 65535.0f / 175.0f;
        float hr = (rh + 6.0f) * 65535.0f / 125.0f;
        tr = std::fmax(0.0f, std::fmin(65535.0f, tr));
        hr = std::fmax(0.0f, std::fmin(65535.0f, hr));
        const uint16_t t = static_cast<uint16_t>(std::lround(tr));
        const uint16_t h = static_cast<uint16_t>(std::lround(hr));
        f[0] = static_cast<uint8_t>(t >> 8);
        f[1] = static_cast<uint8_t>(t & 0xFF);
        f[2] = sht4xCrc(f, 2);
        f[3] = static_cast<uint8_t>(h >> 8);
        f[4] = static_cast<uint8_t>(h & 0xFF);
        f[5] = sht4xCrc(f + 3, 2);
    }
};

// Couples the plant and the controller with a 250 ms tick.
struct Rig {
    DryerController ctl;
    Plant plant;
    uint32_t nowMs = 1000;
    ControllerOutputs out;
    uint8_t seq = 0;
    // Statistics collected while running.
    float maxChamberC = -100.0f;
    float maxHeaterC = -100.0f;
    bool invariantViolated = false;

    explicit Rig(HardwareFeatures hw = HardwareFeatures()) : ctl(hw) {
        ctl.begin(nowMs, ResetCause::POWER_ON, 0, ErrorCode::NONE);
        tick();
    }

    void tick() {
        ControllerInputs in = plant.read(nowMs, out.fan);
        out = ctl.update(in);
        const DeviceState s = ctl.snapshot().state;
        const bool heatingState = s == DeviceState::PREHEATING || s == DeviceState::DRYING;
        if ((out.heaterDuty > 0 || out.relay) && !heatingState) invariantViolated = true;
        if (out.heaterDuty > 100) invariantViolated = true;
        if (heatingState && !out.fan) invariantViolated = true;
        plant.step(out, 0.25f);
        nowMs += 250;
        if (plant.chamberC > maxChamberC) maxChamberC = plant.chamberC;
        if (plant.heaterOutletC > maxHeaterC) maxHeaterC = plant.heaterOutletC;
    }

    void runSeconds(float s) {
        const int n = static_cast<int>(s * 4.0f);
        for (int i = 0; i < n; ++i) tick();
    }

    // Runs until predicate or timeout; returns true if predicate became true.
    template <typename P>
    bool runUntil(P pred, float maxSeconds) {
        const int n = static_cast<int>(maxSeconds * 4.0f);
        for (int i = 0; i < n; ++i) {
            if (pred()) return true;
            tick();
        }
        return pred();
    }

    Response send(Opcode op, const uint8_t* payload = nullptr, uint8_t len = 0) {
        uint8_t frame[64];
        const size_t n = encodeCommandFrame(op, ++seq, payload, len, frame, sizeof(frame));
        Command cmd;
        ResultCode rc;
        if (!decodeCommand(frame, n, cmd, rc)) return DryerController::nack(seq, static_cast<uint8_t>(op), rc);
        return ctl.handleCommand(cmd, nowMs);
    }

    Response start(Material m, float targetC, uint32_t durationSec, FanMode fan = FanMode::AUTO) {
        uint8_t p[12];
        ByteWriter w(p, sizeof(p));
        w.u8(static_cast<uint8_t>(m));
        w.i16(static_cast<int16_t>(std::lround(targetC * 100.0f)));
        w.u32(durationSec);
        w.u32(1790000000u);
        w.u8(static_cast<uint8_t>(fan));
        return send(Opcode::START_SESSION, p, static_cast<uint8_t>(w.size()));
    }

    DeviceState state() const { return ctl.snapshot().state; }
    ErrorCode error() const { return ctl.snapshot().error; }
};

}  // namespace sim
