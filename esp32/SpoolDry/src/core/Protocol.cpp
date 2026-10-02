#include "Protocol.h"

#include <math.h>
#include <string.h>

#include "Bytes.h"

namespace spooldry {

int16_t toCentiC(float c, bool valid) {
    if (!valid || isnan(c)) return kInvalidTemperature;
    float v = roundf(c * 100.0f);
    if (v < -32767.0f) v = -32767.0f;
    if (v > 32767.0f) v = 32767.0f;
    return static_cast<int16_t>(v);
}

uint16_t toCentiRh(float rh, bool valid) {
    if (!valid || isnan(rh)) return kInvalidHumidity;
    float v = roundf(rh * 100.0f);
    if (v < 0.0f) v = 0.0f;
    if (v > 10000.0f) v = 10000.0f;
    return static_cast<uint16_t>(v);
}

float fromCentiC(int16_t v) { return static_cast<float>(v) / 100.0f; }

bool isValidMaterial(uint8_t v) { return v < kMaterialCount; }
bool isValidFanMode(uint8_t v) { return v <= static_cast<uint8_t>(FanMode::OFF); }

static uint8_t expectedPayload(Opcode op) {
    switch (op) {
        case Opcode::START_SESSION: return 12;
        case Opcode::STOP_SESSION: return 0;
        case Opcode::SET_TARGET_TEMP: return 2;
        case Opcode::SET_DURATION: return 4;
        case Opcode::SET_FILAMENT: return 1;
        case Opcode::SET_FAN_MODE: return 1;
        case Opcode::REQUEST_STATUS: return 0;
        case Opcode::RESET_SESSION: return 0;
        case Opcode::IDENTIFY: return 0;
        case Opcode::SET_DEVICE_NAME: return 0xFF;  // variable
    }
    return 0xFE;  // unknown
}

bool decodeCommand(const uint8_t* data, size_t len, Command& out, ResultCode& result) {
    out = Command();
    if (data == nullptr || len < kCommandHeaderSize) {
        result = ResultCode::BAD_LENGTH;
        if (data != nullptr && len >= 3) {
            out.opcode = static_cast<Opcode>(data[1]);
            out.seq = data[2];
        }
        return false;
    }
    out.version = data[0];
    out.opcode = static_cast<Opcode>(data[1]);
    out.seq = data[2];
    const uint8_t plen = data[3];
    if (out.version != kProtocolVersion) {
        result = ResultCode::UNSUPPORTED_VERSION;
        return false;
    }
    if (plen > kMaxCommandPayload || len != kCommandHeaderSize + plen) {
        result = ResultCode::BAD_LENGTH;
        return false;
    }
    const uint8_t expected = expectedPayload(out.opcode);
    if (expected == 0xFE) {
        result = ResultCode::UNKNOWN_OPCODE;
        return false;
    }
    if (expected == 0xFF) {
        if (plen < 1 || plen > kMaxDeviceNameLen) {
            result = ResultCode::BAD_LENGTH;
            return false;
        }
    } else if (plen != expected) {
        result = ResultCode::BAD_LENGTH;
        return false;
    }

    ByteReader r(data + kCommandHeaderSize, plen);
    uint8_t b = 0;
    switch (out.opcode) {
        case Opcode::START_SESSION: {
            r.u8(b);
            r.i16(out.targetCentiC);
            r.u32(out.durationSec);
            r.u32(out.unixTime);
            uint8_t fm = 0;
            r.u8(fm);
            if (!isValidMaterial(b) || !isValidFanMode(fm)) {
                result = ResultCode::INVALID_PARAMETER;
                return false;
            }
            out.material = static_cast<Material>(b);
            out.fanMode = static_cast<FanMode>(fm);
            if (out.targetCentiC < kMinTargetCentiC || out.targetCentiC > kMaxTargetCentiC ||
                out.durationSec < kMinDurationSec || out.durationSec > kMaxDurationSec) {
                result = ResultCode::INVALID_PARAMETER;
                return false;
            }
            break;
        }
        case Opcode::SET_TARGET_TEMP:
            r.i16(out.targetCentiC);
            if (out.targetCentiC < kMinTargetCentiC || out.targetCentiC > kMaxTargetCentiC) {
                result = ResultCode::INVALID_PARAMETER;
                return false;
            }
            break;
        case Opcode::SET_DURATION:
            r.u32(out.durationSec);
            if (out.durationSec < kMinDurationSec || out.durationSec > kMaxDurationSec) {
                result = ResultCode::INVALID_PARAMETER;
                return false;
            }
            break;
        case Opcode::SET_FILAMENT:
            r.u8(b);
            if (!isValidMaterial(b)) {
                result = ResultCode::INVALID_PARAMETER;
                return false;
            }
            out.material = static_cast<Material>(b);
            break;
        case Opcode::SET_FAN_MODE:
            r.u8(b);
            if (!isValidFanMode(b)) {
                result = ResultCode::INVALID_PARAMETER;
                return false;
            }
            out.fanMode = static_cast<FanMode>(b);
            break;
        case Opcode::SET_DEVICE_NAME: {
            const uint8_t* p = data + kCommandHeaderSize;
            for (uint8_t i = 0; i < plen; ++i) {
                // Printable ASCII and UTF-8 continuation/lead bytes allowed; control chars rejected.
                if (p[i] < 0x20 || p[i] == 0x7F) {
                    result = ResultCode::INVALID_PARAMETER;
                    return false;
                }
                out.name[i] = static_cast<char>(p[i]);
            }
            out.name[plen] = '\0';
            break;
        }
        case Opcode::STOP_SESSION:
        case Opcode::REQUEST_STATUS:
        case Opcode::RESET_SESSION:
        case Opcode::IDENTIFY:
            break;
    }
    result = ResultCode::OK;
    return true;
}

size_t encodeDeviceInfo(const DeviceInfo& i, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.u8(i.protocolVersion);
    w.u8(i.hardwareRevision);
    w.bytes(i.deviceId, 6);
    w.u8(i.fwMajor);
    w.u8(i.fwMinor);
    w.u8(i.fwPatch);
    w.i16(i.minTargetCentiC);
    w.i16(i.maxTargetCentiC);
    w.u32(i.maxDurationSec);
    w.u16(i.capabilities);
    w.u8(i.resetReason);
    w.u8(i.lastFault);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeDeviceStatus(const Snapshot& s, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.u8(kProtocolVersion);
    w.u8(static_cast<uint8_t>(s.state));
    w.u8(static_cast<uint8_t>(s.error));
    w.u8(s.flags);
    w.i16(s.chamberCentiC);
    w.u16(s.humidityCentiRh);
    w.i16(s.heaterCentiC);
    w.i16(s.targetCentiC);
    w.u32(s.remainingSec);
    w.u32(s.elapsedDryingSec);
    w.u32(s.sessionId);
    w.u8(static_cast<uint8_t>(s.material));
    w.u8(s.heaterDuty);
    w.u16(s.fanRpm);
    w.u32(s.uptimeSec);
    w.u8(static_cast<uint8_t>(s.fanMode));
    w.u8(static_cast<uint8_t>(s.endReason));
    w.u16(s.statusSeq);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeTemperature(const Snapshot& s, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.i16(s.chamberCentiC);
    w.i16(s.heaterCentiC);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeHumidity(const Snapshot& s, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.u16(s.humidityCentiRh);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeHeaterState(const Snapshot& s, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    uint8_t f = 0;
    if (s.relayOn) f |= 0x01;
    if (s.heaterOutputOn) f |= 0x02;
    w.u8(f);
    w.u8(s.heaterDuty);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeFanState(const Snapshot& s, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.u8(static_cast<uint8_t>(s.fanMode));
    w.u8(s.fanOn ? 1 : 0);
    w.u16(s.fanRpm);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeDryingSession(const Snapshot& s, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.u32(s.sessionId);
    w.u8(static_cast<uint8_t>(s.material));
    w.u8(static_cast<uint8_t>(s.endReason));
    w.i16(s.targetCentiC);
    w.u32(s.durationSec);
    w.u32(s.elapsedDryingSec);
    w.u32(s.startUnixTime);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeTargetTemp(const Snapshot& s, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.i16(s.targetCentiC);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeRemainingTime(const Snapshot& s, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.u32(s.remainingSec);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeResponse(const Response& r, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.u8(kProtocolVersion);
    w.u8(static_cast<uint8_t>(r.type));
    w.u8(r.seq);
    w.u8(r.opcode);
    w.u8(static_cast<uint8_t>(r.result));
    const uint8_t n = r.payloadLen > kMaxResponsePayload ? kMaxResponsePayload : r.payloadLen;
    w.u8(n);
    w.bytes(r.payload, n);
    return w.overflowed() ? 0 : w.size();
}

size_t encodeCommandFrame(Opcode op, uint8_t seq, const uint8_t* payload, uint8_t payloadLen, uint8_t* buf, size_t cap) {
    ByteWriter w(buf, cap);
    w.u8(kProtocolVersion);
    w.u8(static_cast<uint8_t>(op));
    w.u8(seq);
    w.u8(payloadLen);
    if (payloadLen > 0 && payload != nullptr) w.bytes(payload, payloadLen);
    return w.overflowed() ? 0 : w.size();
}

const char* stateName(DeviceState s) {
    switch (s) {
        case DeviceState::DISCONNECTED: return "DISCONNECTED";
        case DeviceState::CONNECTING: return "CONNECTING";
        case DeviceState::CONNECTED: return "CONNECTED";
        case DeviceState::IDLE: return "IDLE";
        case DeviceState::PREHEATING: return "PREHEATING";
        case DeviceState::DRYING: return "DRYING";
        case DeviceState::COOLDOWN: return "COOLDOWN";
        case DeviceState::COMPLETED: return "COMPLETED";
        case DeviceState::ERROR: return "ERROR";
        case DeviceState::OVER_TEMPERATURE: return "OVER_TEMPERATURE";
    }
    return "?";
}

const char* errorName(ErrorCode e) {
    switch (e) {
        case ErrorCode::NONE: return "NONE";
        case ErrorCode::SENSOR_I2C: return "SENSOR_I2C";
        case ErrorCode::SENSOR_CRC: return "SENSOR_CRC";
        case ErrorCode::SENSOR_RANGE: return "SENSOR_RANGE";
        case ErrorCode::NTC_OPEN: return "NTC_OPEN";
        case ErrorCode::NTC_SHORT: return "NTC_SHORT";
        case ErrorCode::OVER_TEMP_CHAMBER: return "OVER_TEMP_CHAMBER";
        case ErrorCode::OVER_TEMP_HEATER: return "OVER_TEMP_HEATER";
        case ErrorCode::PREHEAT_TIMEOUT: return "PREHEAT_TIMEOUT";
        case ErrorCode::HEATING_INEFFECTIVE: return "HEATING_INEFFECTIVE";
        case ErrorCode::HEATER_STUCK_ON: return "HEATER_STUCK_ON";
        case ErrorCode::FAN_FAILURE: return "FAN_FAILURE";
        case ErrorCode::SESSION_TIME_LIMIT: return "SESSION_TIME_LIMIT";
        case ErrorCode::UNEXPECTED_RESET: return "UNEXPECTED_RESET";
        case ErrorCode::INTERNAL: return "INTERNAL";
    }
    return "?";
}

}  // namespace spooldry
