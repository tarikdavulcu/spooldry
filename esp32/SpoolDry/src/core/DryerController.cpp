#include "DryerController.h"

#include <math.h>
#include <string.h>

#include "Bytes.h"

namespace spooldry {

using namespace limits;

DryerController::DryerController(HardwareFeatures features) : hw_(features) {}

uint16_t DryerController::capabilities() const {
    uint16_t c = Capability::IDENTIFY_LED | Capability::LOCAL_BUTTON;
    if (hw_.heaterNtc) c |= Capability::HEATER_NTC;
    if (hw_.fanTach) c |= Capability::FAN_TACH;
    if (hw_.safetyRelay) c |= Capability::SAFETY_RELAY;
    // Capability::OTA_BLE is intentionally NOT advertised: BLE OTA is not part of firmware 1.0.
    return c;
}

void DryerController::begin(uint32_t nowMs, ResetCause cause, uint32_t sessionCounter, ErrorCode lastFault) {
    // A reboot never resumes a session. Heater outputs are already OFF (HAL drives them low first).
    state_ = DeviceState::IDLE;
    endReason_ = EndReason::NONE;
    sessionCounter_ = sessionCounter;
    lastLatchedFault_ = lastFault;
    bootMs_ = nowMs;
    lastUpdateMs_ = nowMs;
    started_ = true;
    error_ = ErrorCode::NONE;
    if (cause == ResetCause::PANIC || cause == ResetCause::WATCHDOG || cause == ResetCause::BROWNOUT) {
        // Informational: shown to the user until the next command clears it.
        error_ = ErrorCode::UNEXPECTED_RESET;
        lastLatchedFault_ = ErrorCode::UNEXPECTED_RESET;
    }
    resetTrackers(nowMs);
    ControllerOutputs off;
    refreshSnapshot(nowMs, off);
}

uint32_t DryerController::unixTimeAt(uint32_t nowMs) const {
    if (!timeSynced_) return 0;
    return unixAtSync_ + (nowMs - syncMs_) / 1000UL;
}

bool DryerController::takePendingName(char* out, size_t cap) {
    if (!namePending_ || cap == 0) return false;
    size_t i = 0;
    for (; i + 1 < cap && pendingName_[i] != '\0'; ++i) out[i] = pendingName_[i];
    out[i] = '\0';
    namePending_ = false;
    return true;
}

void DryerController::resetTrackers(uint32_t now) {
    overTarget_.stop();
    overTargetArmed_ = false;
    underTemp_.stop();
    fanLow_.stop();
    ntcImplausible_.stop();
    runawayWindow_.stop();
    runawayDutySum_ = 0.0f;
    runawaySamples_ = 0;
    stuckWindow_.stop();
    integral_ = 0.0f;
    duty_ = 0.0f;
    (void)now;
}

void DryerController::enterError(ErrorCode code, uint32_t now) {
    if (state_ == DeviceState::OVER_TEMPERATURE) return;  // over-temperature has priority
    if (state_ == DeviceState::ERROR) return;             // first fault wins (root cause is preserved)
    if (sessionActive()) endReason_ = EndReason::ERROR;
    if (state_ == DeviceState::DRYING) elapsedDryingMs_ = now - dryingStartMs_;
    if (heating()) heatingEndedMs_ = now;
    state_ = DeviceState::ERROR;
    error_ = code;
    lastLatchedFault_ = code;
    phaseStartMs_ = now;
    resetTrackers(now);
}

void DryerController::enterOverTemp(ErrorCode code, uint32_t now) {
    if (state_ == DeviceState::OVER_TEMPERATURE) return;
    if (sessionActive()) endReason_ = EndReason::OVER_TEMPERATURE;
    if (state_ == DeviceState::DRYING) elapsedDryingMs_ = now - dryingStartMs_;
    if (heating()) heatingEndedMs_ = now;
    state_ = DeviceState::OVER_TEMPERATURE;
    error_ = code;
    lastLatchedFault_ = code;
    phaseStartMs_ = now;
    resetTrackers(now);
}

void DryerController::enterCooldown(EndReason reason, uint32_t now) {
    if (state_ == DeviceState::DRYING) elapsedDryingMs_ = now - dryingStartMs_;
    heatingEndedMs_ = now;
    endReason_ = reason;
    state_ = DeviceState::COOLDOWN;
    phaseStartMs_ = now;
    resetTrackers(now);
}

Response DryerController::nack(uint8_t seq, uint8_t opcode, ResultCode rc) {
    Response r;
    r.type = ResponseType::NACK;
    r.seq = seq;
    r.opcode = opcode;
    r.result = rc;
    return r;
}

Response DryerController::ack(const Command& cmd) const {
    Response r;
    r.type = ResponseType::ACK;
    r.seq = cmd.seq;
    r.opcode = static_cast<uint8_t>(cmd.opcode);
    r.result = ResultCode::OK;
    return r;
}

Response DryerController::nackState(const Command& cmd, ResultCode rc) const {
    Response r = nack(cmd.seq, static_cast<uint8_t>(cmd.opcode), rc);
    r.payload[0] = static_cast<uint8_t>(state_);
    r.payload[1] = static_cast<uint8_t>(error_);
    r.payloadLen = 2;
    return r;
}

Response DryerController::handleCommand(const Command& cmd, uint32_t now) {
    switch (cmd.opcode) {
        case Opcode::START_SESSION: {
            if (state_ == DeviceState::ERROR || state_ == DeviceState::OVER_TEMPERATURE)
                return nackState(cmd, ResultCode::NOT_ALLOWED_IN_STATE);
            if (sessionActive()) return nackState(cmd, ResultCode::BUSY);
            if (!chamberValid_ || !humidityValid_) return nackState(cmd, ResultCode::SENSOR_FAULT);
            if (hw_.heaterNtc && !heaterValid_) return nackState(cmd, ResultCode::SENSOR_FAULT);
            material_ = cmd.material;
            targetC_ = fromCentiC(cmd.targetCentiC);
            durationSec_ = cmd.durationSec;
            fanMode_ = cmd.fanMode;
            timeSynced_ = true;
            unixAtSync_ = cmd.unixTime;
            syncMs_ = now;
            startUnix_ = cmd.unixTime;
            sessionCounter_++;
            sessionId_ = sessionCounter_;
            sessionStartMs_ = now;
            phaseStartMs_ = now;
            dryingStartMs_ = now;
            elapsedDryingMs_ = 0;
            endReason_ = EndReason::NONE;
            error_ = ErrorCode::NONE;
            resetTrackers(now);
            state_ = DeviceState::PREHEATING;
            Response r = ack(cmd);
            ByteWriter w(r.payload, sizeof(r.payload));
            w.u32(sessionId_);
            w.u32(unixTimeAt(now));
            r.payloadLen = static_cast<uint8_t>(w.size());
            return r;
        }
        case Opcode::STOP_SESSION:
            if (heating()) enterCooldown(EndReason::STOPPED_BY_USER, now);
            return ack(cmd);
        case Opcode::SET_TARGET_TEMP:
            if (state_ == DeviceState::ERROR || state_ == DeviceState::OVER_TEMPERATURE)
                return nackState(cmd, ResultCode::NOT_ALLOWED_IN_STATE);
            targetC_ = fromCentiC(cmd.targetCentiC);
            overTarget_.stop();
            overTargetArmed_ = false;  // a lowered target must not trip over-temperature while cooling
            underTemp_.stop();
            return ack(cmd);
        case Opcode::SET_DURATION:
            if (state_ == DeviceState::ERROR || state_ == DeviceState::OVER_TEMPERATURE)
                return nackState(cmd, ResultCode::NOT_ALLOWED_IN_STATE);
            durationSec_ = cmd.durationSec;  // in DRYING, completion is re-evaluated on the next tick
            return ack(cmd);
        case Opcode::SET_FILAMENT:
            material_ = cmd.material;
            return ack(cmd);
        case Opcode::SET_FAN_MODE:
            if (cmd.fanMode == FanMode::OFF &&
                (sessionActive() || state_ == DeviceState::ERROR || state_ == DeviceState::OVER_TEMPERATURE))
                return nackState(cmd, ResultCode::NOT_ALLOWED_IN_STATE);
            fanMode_ = cmd.fanMode;
            return ack(cmd);
        case Opcode::REQUEST_STATUS:
            return ack(cmd);
        case Opcode::RESET_SESSION:
            if (sessionActive()) return nackState(cmd, ResultCode::BUSY);
            if (state_ == DeviceState::OVER_TEMPERATURE) {
                const bool chamberCool = chamberValid_ && chamberC_ < kOverTempResetBelowC;
                const bool heaterCool = !hw_.heaterNtc || (heaterValid_ && heaterC_ < kHeaterResetBelowC);
                if (!chamberCool || !heaterCool) return nackState(cmd, ResultCode::OVER_TEMPERATURE_LOCK);
            }
            if (state_ == DeviceState::ERROR) {
                if (!chamberValid_ || (hw_.heaterNtc && !heaterValid_)) return nackState(cmd, ResultCode::SENSOR_FAULT);
            }
            state_ = DeviceState::IDLE;
            error_ = ErrorCode::NONE;
            endReason_ = EndReason::NONE;
            resetTrackers(now);
            return ack(cmd);
        case Opcode::IDENTIFY:
            identifyUntilMs_ = now + 5000;
            identifyActive_ = true;
            return ack(cmd);
        case Opcode::SET_DEVICE_NAME:
            memcpy(pendingName_, cmd.name, sizeof(pendingName_));
            pendingName_[kMaxDeviceNameLen] = '\0';
            namePending_ = true;
            return ack(cmd);
    }
    return nack(cmd.seq, static_cast<uint8_t>(cmd.opcode), ResultCode::UNKNOWN_OPCODE);
}

void DryerController::localStop(uint32_t now) {
    if (heating()) enterCooldown(EndReason::STOPPED_ON_DEVICE, now);
}

bool DryerController::localReset(uint32_t now) {
    Command c;
    c.version = kProtocolVersion;
    c.opcode = Opcode::RESET_SESSION;
    return handleCommand(c, now).result == ResultCode::OK;
}

float DryerController::computeDuty(float dtSec) {
    if (!heating() || !chamberValid_) {
        integral_ = 0.0f;
        return 0.0f;
    }
    const float err = targetC_ - chamberC_;
    const float p = control::kKp * err;
    float raw = p + integral_;
    // Conditional integration (anti-windup): integrate only when not pushing further into saturation.
    const bool saturatedHigh = raw >= 100.0f && err > 0.0f;
    const bool saturatedLow = raw <= 0.0f && err < 0.0f;
    if (!saturatedHigh && !saturatedLow) {
        integral_ += control::kKi * err * dtSec;
        if (integral_ < control::kIntegralMin) integral_ = control::kIntegralMin;
        if (integral_ > control::kIntegralMax) integral_ = control::kIntegralMax;
    }
    raw = p + integral_;
    if (raw < 0.0f) raw = 0.0f;
    if (raw > 100.0f) raw = 100.0f;
    // Heater-outlet derating (independent of the chamber loop).
    if (hw_.heaterNtc && heaterValid_ && heaterC_ > kHeaterDerateStartC) {
        const float span = kHeaterDerateZeroC - kHeaterDerateStartC;
        float k = 1.0f - (heaterC_ - kHeaterDerateStartC) / span;
        if (k < 0.0f) k = 0.0f;
        raw *= k;
    }
    // Soft start: limit how fast duty can rise (decreases are immediate).
    const float maxRise = kDutySlewPerSec * dtSec;
    if (raw > duty_ + maxRise) raw = duty_ + maxRise;
    return raw;
}

bool DryerController::computeFan() const {
    // Airflow is mandatory whenever the heater may be hot.
    if (sessionActive() || state_ == DeviceState::OVER_TEMPERATURE) return true;
    if (state_ == DeviceState::ERROR) {
        // Keep cooling after a fault while the chamber is warm (or unknown).
        return !chamberValid_ || chamberC_ >= kFanAutoOnAboveC || fanMode_ == FanMode::ON;
    }
    switch (fanMode_) {
        case FanMode::ON: return true;
        case FanMode::OFF: return false;
        case FanMode::AUTO: return chamberValid_ && chamberC_ >= kFanAutoOnAboveC;
    }
    return true;
}

ControllerOutputs DryerController::update(const ControllerInputs& in) {
    const uint32_t now = in.nowMs;
    uint32_t dtMs = started_ ? now - lastUpdateMs_ : control::kTickMs;
    if (dtMs > 2000) dtMs = 2000;
    lastUpdateMs_ = now;
    started_ = true;
    const float dt = static_cast<float>(dtMs) / 1000.0f;

    // ---- 1. Ingest sensors -------------------------------------------------------------
    if (in.chamber.valid) {
        chamberValid_ = true;
        chamberC_ = in.chamber.temperatureC;
        humidity_ = in.chamber.humidityRh;
        humidityValid_ = !isnan(in.chamber.humidityRh);
        chamberFault_ = ErrorCode::NONE;
        chamberInvalid_.stop();
    } else {
        chamberValid_ = false;
        humidityValid_ = false;
        chamberFault_ = in.chamber.fault == ErrorCode::NONE ? ErrorCode::SENSOR_I2C : in.chamber.fault;
        chamberInvalid_.start(now);
    }
    if (hw_.heaterNtc) {
        if (in.heater.valid) {
            heaterValid_ = true;
            heaterC_ = in.heater.temperatureC;
            heaterFault_ = ErrorCode::NONE;
            heaterInvalid_.stop();
        } else {
            heaterValid_ = false;
            heaterFault_ = in.heater.fault == ErrorCode::NONE ? ErrorCode::NTC_OPEN : in.heater.fault;
            heaterInvalid_.start(now);
        }
    }
    fanRpm_ = in.fanRpm;
    const bool chamberLatched = chamberInvalid_.elapsed(now, kSensorFaultDebounceMs);
    const bool heaterLatched = hw_.heaterNtc && heaterInvalid_.elapsed(now, kSensorFaultDebounceMs);

    // ---- 2. Absolute limits (any state) -------------------------------------------------
    if (chamberValid_ && chamberC_ >= kAbsoluteChamberMaxC) enterOverTemp(ErrorCode::OVER_TEMP_CHAMBER, now);
    if (hw_.heaterNtc && heaterValid_ && heaterC_ >= kHeaterAbsoluteMaxC) enterOverTemp(ErrorCode::OVER_TEMP_HEATER, now);

    // ---- 3. Session supervision -------------------------------------------------------------
    if (heating()) {
        if (chamberLatched) enterError(chamberFault_, now);
        else if (heaterLatched) enterError(heaterFault_, now);
    }
    if (heating()) {
        // Sustained over-target. Only armed after the chamber has been below target + margin, so a
        // session started in a hot chamber, or a lowered target, does not trip while cooling down.
        if (chamberValid_ && chamberC_ < targetC_ + kOverTargetMarginC) overTargetArmed_ = true;
        if (overTargetArmed_ && chamberValid_ && chamberC_ >= targetC_ + kOverTargetMarginC) {
            overTarget_.start(now);
            if (overTarget_.elapsed(now, kOverTargetHoldMs)) enterOverTemp(ErrorCode::OVER_TEMP_CHAMBER, now);
        } else {
            overTarget_.stop();
        }
    }
    if (heating() && hw_.heaterNtc && chamberValid_ && heaterValid_) {
        // Outlet NTC must not read far below the chamber while the heater is driven (detached/open NTC).
        if (duty_ >= 30.0f && heaterC_ < chamberC_ - ntc::kImplausibleBelowChamberC) {
            ntcImplausible_.start(now);
            if (ntcImplausible_.elapsed(now, ntc::kImplausibleHoldMs)) enterError(ErrorCode::NTC_OPEN, now);
        } else {
            ntcImplausible_.stop();
        }
    }
    if (heating() && (now - sessionStartMs_) >= durationSec_ * 1000UL + kSessionSlackMs + kPreheatTimeoutMs) {
        enterError(ErrorCode::SESSION_TIME_LIMIT, now);
    }
    if ((sessionActive()) && hw_.fanTach && fanCommanded_ && fanOn_.elapsed(now, kFanSpinUpMs)) {
        if (fanRpm_ < kFanMinRpm) {
            fanLow_.start(now);
            if (fanLow_.elapsed(now, kFanFaultHoldMs)) enterError(ErrorCode::FAN_FAILURE, now);
        } else {
            fanLow_.stop();
        }
    }

    // ---- 4. Phase transitions ---------------------------------------------------------------
    if (state_ == DeviceState::PREHEATING) {
        if (now - phaseStartMs_ >= kPreheatTimeoutMs) {
            enterError(ErrorCode::PREHEAT_TIMEOUT, now);
        } else if (chamberValid_ && chamberC_ >= targetC_ - kPreheatBandC) {
            state_ = DeviceState::DRYING;
            dryingStartMs_ = now;
            elapsedDryingMs_ = 0;
            phaseStartMs_ = now;
            runawayWindow_.stop();
        } else if (chamberValid_) {
            // Thermal-runaway style check: heating hard must produce a temperature rise.
            if (!runawayWindow_.active) {
                runawayWindow_.restart(now);
                runawayStartC_ = chamberC_;
                runawayDutySum_ = 0.0f;
                runawaySamples_ = 0;
            }
            runawayDutySum_ += duty_;
            runawaySamples_++;
            if (runawayWindow_.elapsed(now, kRunawayWindowMs)) {
                const float avgDuty = runawaySamples_ ? runawayDutySum_ / static_cast<float>(runawaySamples_) : 0.0f;
                if (avgDuty >= kRunawayMinAvgDuty && (chamberC_ - runawayStartC_) < kRunawayMinRiseC) {
                    enterError(ErrorCode::HEATING_INEFFECTIVE, now);
                } else {
                    runawayWindow_.stop();
                }
            }
        }
    }
    if (state_ == DeviceState::DRYING) {
        elapsedDryingMs_ = now - dryingStartMs_;
        if (elapsedDryingMs_ >= durationSec_ * 1000UL) {
            enterCooldown(EndReason::COMPLETED, now);
        } else if (chamberValid_ && chamberC_ < targetC_ - kDryingUnderTempC) {
            underTemp_.start(now);
            if (underTemp_.elapsed(now, kDryingUnderTempMs)) enterError(ErrorCode::HEATING_INEFFECTIVE, now);
        } else {
            underTemp_.stop();
        }
    }
    if (state_ == DeviceState::COOLDOWN) {
        const bool cool = chamberValid_ && chamberC_ <= kCooldownEndC;
        if (cool || (now - phaseStartMs_) >= kCooldownMaxMs) {
            state_ = (endReason_ == EndReason::COMPLETED) ? DeviceState::COMPLETED : DeviceState::IDLE;
            phaseStartMs_ = now;
        }
    }

    // ---- 5. Heater-stuck detection (heater commanded off) -----------------------------------
    if (!heating() && state_ != DeviceState::OVER_TEMPERATURE && chamberValid_) {
        if (!stuckWindow_.active) {
            stuckWindow_.restart(now);
            stuckStartC_ = chamberC_;
        } else if (stuckWindow_.elapsed(now, kStuckWindowMs)) {
            if (chamberC_ - stuckStartC_ >= kStuckRiseC && chamberC_ >= kStuckMinTempC) {
                enterError(ErrorCode::HEATER_STUCK_ON, now);
            }
            stuckWindow_.restart(now);
            stuckStartC_ = chamberC_;
        }
    } else if (heating()) {
        stuckWindow_.stop();
    }
    // Outlet much hotter than the chamber while the heater is commanded off => current still flows.
    // Skipped for a while after heating ends so residual PTC heat is not mistaken for a fault.
    if (!heating() && state_ != DeviceState::OVER_TEMPERATURE && hw_.heaterNtc && heaterValid_ && chamberValid_ &&
        (now - heatingEndedMs_) >= kStuckResidualHeatMs && heaterC_ >= chamberC_ + kStuckOutletAboveChamberC) {
        stuckOutlet_.start(now);
        if (stuckOutlet_.elapsed(now, kStuckOutletHoldMs)) enterError(ErrorCode::HEATER_STUCK_ON, now);
    } else {
        stuckOutlet_.stop();
    }

    // ---- 6. Outputs ----------------------------------------------------------------------------
    ControllerOutputs out;
    duty_ = computeDuty(dt);
    out.relay = hw_.safetyRelay ? heating() : false;
    out.heaterDuty = heating() ? static_cast<uint8_t>(lroundf(duty_)) : 0;
    if (!heating()) duty_ = 0.0f;
    out.fan = computeFan();
    if (out.fan && !fanCommanded_) fanOn_.restart(now);
    if (!out.fan) {
        fanOn_.stop();
        fanLow_.stop();
    }
    fanCommanded_ = out.fan;
    if (identifyActive_ && static_cast<int32_t>(now - identifyUntilMs_) >= 0) identifyActive_ = false;
    out.identify = identifyActive_;

    // Invariant: never drive the heater outside a heating state.
    if (!heating()) {
        out.relay = false;
        out.heaterDuty = 0;
    }
    refreshSnapshot(now, out);
    return out;
}

void DryerController::refreshSnapshot(uint32_t now, const ControllerOutputs& out) {
    Snapshot s;
    s.state = state_;
    s.error = error_;
    uint8_t f = 0;
    if (out.relay) f |= StatusFlag::HEATER_RELAY;
    if (out.heaterDuty > 0) f |= StatusFlag::HEATER_OUTPUT;
    if (out.fan) f |= StatusFlag::FAN_ON;
    if (clientConnected_) f |= StatusFlag::CLIENT_CONNECTED;
    if (chamberValid_) f |= StatusFlag::CHAMBER_SENSOR_OK;
    if (!hw_.heaterNtc || heaterValid_) f |= StatusFlag::HEATER_SENSOR_OK;
    if (sessionActive()) f |= StatusFlag::SESSION_ACTIVE;
    if (timeSynced_) f |= StatusFlag::TIME_SYNCED;
    s.flags = f;
    s.chamberCentiC = toCentiC(chamberC_, chamberValid_);
    s.humidityCentiRh = toCentiRh(humidity_, humidityValid_);
    s.heaterCentiC = toCentiC(heaterC_, hw_.heaterNtc && heaterValid_);
    s.targetCentiC = toCentiC(targetC_, true);
    s.durationSec = durationSec_;
    switch (state_) {
        case DeviceState::PREHEATING:
            s.remainingSec = durationSec_;
            s.elapsedDryingSec = 0;
            break;
        case DeviceState::DRYING: {
            const uint32_t el = elapsedDryingMs_ / 1000UL;
            s.elapsedDryingSec = el;
            s.remainingSec = el >= durationSec_ ? 0 : durationSec_ - el;
            break;
        }
        case DeviceState::COOLDOWN:
        case DeviceState::COMPLETED:
            s.elapsedDryingSec = elapsedDryingMs_ / 1000UL;
            s.remainingSec = 0;
            break;
        default:
            s.elapsedDryingSec = elapsedDryingMs_ / 1000UL;
            s.remainingSec = kUnknownRemaining;
            break;
    }
    s.sessionId = sessionId_;
    s.material = material_;
    s.heaterDuty = out.heaterDuty;
    s.fanRpm = fanRpm_;
    s.uptimeSec = (now - bootMs_) / 1000UL;
    s.fanMode = fanMode_;
    s.endReason = endReason_;
    s.statusSeq = ++statusSeq_;
    s.startUnixTime = startUnix_;
    s.fanOn = out.fan;
    s.relayOn = out.relay;
    s.heaterOutputOn = out.heaterDuty > 0;
    snap_ = s;
}

}  // namespace spooldry
