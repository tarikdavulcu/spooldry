// SpoolDry BLE Protocol v1 codec. Platform independent (compiled on host for tests).
// Layouts are documented in docs/BLE_PROTOCOL.md and mirrored in the iOS SpoolDryKit package.
#pragma once
#include <stddef.h>
#include <stdint.h>

#include "ProtocolConstants.h"

namespace spooldry {

constexpr size_t kMaxCommandPayload = 32;
constexpr size_t kCommandHeaderSize = 4;   // ver, opcode, seq, len
constexpr size_t kResponseHeaderSize = 6;  // ver, type, seq, opcode, result, len
constexpr size_t kMaxResponsePayload = 10;
constexpr size_t kMaxDeviceNameLen = 20;

// Encoding helpers between floating point and protocol fixed point.
int16_t toCentiC(float c, bool valid);
uint16_t toCentiRh(float rh, bool valid);
float fromCentiC(int16_t v);

struct DeviceInfo {
    uint8_t protocolVersion = kProtocolVersion;
    uint8_t hardwareRevision = kHardwareRevision;
    uint8_t deviceId[6] = {0, 0, 0, 0, 0, 0};
    uint8_t fwMajor = kFirmwareMajor;
    uint8_t fwMinor = kFirmwareMinor;
    uint8_t fwPatch = kFirmwarePatch;
    int16_t minTargetCentiC = kMinTargetCentiC;
    int16_t maxTargetCentiC = kMaxTargetCentiC;
    uint32_t maxDurationSec = kMaxDurationSec;
    uint16_t capabilities = 0;
    uint8_t resetReason = 0;  // see ResetCause
    uint8_t lastFault = 0;    // ErrorCode persisted across reboot
};

// Reset causes reported in DeviceInfo.resetReason.
enum class ResetCause : uint8_t { UNKNOWN = 0, POWER_ON = 1, SOFTWARE = 2, PANIC = 3, WATCHDOG = 4, BROWNOUT = 5, OTHER = 6 };

// Complete device snapshot. Encoded as the 36-byte Device Status characteristic.
struct Snapshot {
    DeviceState state = DeviceState::IDLE;
    ErrorCode error = ErrorCode::NONE;
    uint8_t flags = 0;
    int16_t chamberCentiC = kInvalidTemperature;
    uint16_t humidityCentiRh = kInvalidHumidity;
    int16_t heaterCentiC = kInvalidTemperature;
    int16_t targetCentiC = 0;
    uint32_t remainingSec = kUnknownRemaining;
    uint32_t elapsedDryingSec = 0;
    uint32_t sessionId = 0;
    Material material = Material::CUSTOM;
    uint8_t heaterDuty = 0;
    uint16_t fanRpm = 0;
    uint32_t uptimeSec = 0;
    FanMode fanMode = FanMode::AUTO;
    EndReason endReason = EndReason::NONE;
    uint16_t statusSeq = 0;
    // Additional data used by individual characteristics (not part of Device Status bytes).
    uint32_t durationSec = 0;
    uint32_t startUnixTime = 0;
    bool fanOn = false;
    bool relayOn = false;
    bool heaterOutputOn = false;
};

struct Command {
    uint8_t version = 0;
    Opcode opcode = Opcode::REQUEST_STATUS;
    uint8_t seq = 0;
    // Decoded parameters (only the ones relevant to opcode are meaningful).
    Material material = Material::CUSTOM;
    int16_t targetCentiC = 0;
    uint32_t durationSec = 0;
    uint32_t unixTime = 0;
    FanMode fanMode = FanMode::AUTO;
    char name[kMaxDeviceNameLen + 1] = {0};
};

struct Response {
    ResponseType type = ResponseType::ACK;
    uint8_t seq = 0;
    uint8_t opcode = 0;
    ResultCode result = ResultCode::OK;
    uint8_t payload[kMaxResponsePayload] = {0};
    uint8_t payloadLen = 0;
};

// Decodes a Command characteristic write. On failure, `result` holds the reason and
// `out.seq` / `out.opcode` are filled whenever the header could be read (so a NACK can be matched).
bool decodeCommand(const uint8_t* data, size_t len, Command& out, ResultCode& result);

size_t encodeDeviceInfo(const DeviceInfo& info, uint8_t* buf, size_t cap);
size_t encodeDeviceStatus(const Snapshot& s, uint8_t* buf, size_t cap);
size_t encodeTemperature(const Snapshot& s, uint8_t* buf, size_t cap);
size_t encodeHumidity(const Snapshot& s, uint8_t* buf, size_t cap);
size_t encodeHeaterState(const Snapshot& s, uint8_t* buf, size_t cap);
size_t encodeFanState(const Snapshot& s, uint8_t* buf, size_t cap);
size_t encodeDryingSession(const Snapshot& s, uint8_t* buf, size_t cap);
size_t encodeTargetTemp(const Snapshot& s, uint8_t* buf, size_t cap);
size_t encodeRemainingTime(const Snapshot& s, uint8_t* buf, size_t cap);
size_t encodeResponse(const Response& r, uint8_t* buf, size_t cap);

// Builds a command frame (used by host tests and golden-vector generation).
size_t encodeCommandFrame(Opcode op, uint8_t seq, const uint8_t* payload, uint8_t payloadLen, uint8_t* buf, size_t cap);

bool isValidMaterial(uint8_t v);
bool isValidFanMode(uint8_t v);
const char* stateName(DeviceState s);
const char* errorName(ErrorCode e);

}  // namespace spooldry
