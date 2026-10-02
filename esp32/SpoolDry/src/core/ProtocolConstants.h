// GENERATED FILE - DO NOT EDIT. Source: protocol/spooldry-ble-v1.json (tools/gen_protocol.py)
#pragma once
#include <stdint.h>

namespace spooldry {

constexpr uint8_t kProtocolVersion = 1;
constexpr uint8_t kHardwareRevision = 1;
constexpr uint8_t kFirmwareMajor = 1;
constexpr uint8_t kFirmwareMinor = 0;
constexpr uint8_t kFirmwarePatch = 0;
constexpr const char* kFirmwareVersionString = "1.0.0";
constexpr const char* kAdvertisedNamePrefix = "SpoolDry-";

constexpr const char* kServiceUUID = "5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharDeviceInfoUUID = "5D0F0002-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharTemperatureUUID = "5D0F0003-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharHumidityUUID = "5D0F0004-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharHeaterStateUUID = "5D0F0005-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharFanStateUUID = "5D0F0006-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharDryingSessionUUID = "5D0F0007-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharTargetTempUUID = "5D0F0008-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharRemainingTimeUUID = "5D0F0009-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharDeviceStatusUUID = "5D0F000A-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharCommandUUID = "5D0F000B-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharCommandResponseUUID = "5D0F000C-2B7E-4C8A-9B1E-53504F4F4C44";
constexpr const char* kCharFirmwareVersionUUID = "5D0F000D-2B7E-4C8A-9B1E-53504F4F4C44";

constexpr uint8_t kSizeDeviceInfo = 23;
constexpr uint8_t kSizeTemperature = 4;
constexpr uint8_t kSizeHumidity = 2;
constexpr uint8_t kSizeHeaterState = 2;
constexpr uint8_t kSizeFanState = 4;
constexpr uint8_t kSizeDryingSession = 20;
constexpr uint8_t kSizeTargetTemp = 2;
constexpr uint8_t kSizeRemainingTime = 4;
constexpr uint8_t kSizeDeviceStatus = 36;
constexpr uint8_t kSizeCommand = 36;
constexpr uint8_t kSizeCommandResponse = 16;
constexpr uint8_t kSizeFirmwareVersion = 16;

enum class DeviceState : uint8_t {
    DISCONNECTED = 0,
    CONNECTING = 1,
    CONNECTED = 2,
    IDLE = 3,
    PREHEATING = 4,
    DRYING = 5,
    COOLDOWN = 6,
    COMPLETED = 7,
    ERROR = 8,
    OVER_TEMPERATURE = 9,
};
enum class Opcode : uint8_t {
    START_SESSION = 1,
    STOP_SESSION = 2,
    SET_TARGET_TEMP = 3,
    SET_DURATION = 4,
    SET_FILAMENT = 5,
    SET_FAN_MODE = 6,
    REQUEST_STATUS = 7,
    RESET_SESSION = 8,
    IDENTIFY = 9,
    SET_DEVICE_NAME = 10,
};
enum class ResponseType : uint8_t {
    ACK = 128,
    NACK = 129,
};
enum class ResultCode : uint8_t {
    OK = 0,
    UNKNOWN_OPCODE = 1,
    BAD_LENGTH = 2,
    UNSUPPORTED_VERSION = 3,
    INVALID_PARAMETER = 4,
    BUSY = 5,
    NOT_ALLOWED_IN_STATE = 6,
    SENSOR_FAULT = 7,
    OVER_TEMPERATURE_LOCK = 8,
    INTERNAL_ERROR = 9,
};
enum class ErrorCode : uint8_t {
    NONE = 0,
    SENSOR_I2C = 1,
    SENSOR_CRC = 2,
    SENSOR_RANGE = 3,
    NTC_OPEN = 4,
    NTC_SHORT = 5,
    OVER_TEMP_CHAMBER = 6,
    OVER_TEMP_HEATER = 7,
    PREHEAT_TIMEOUT = 8,
    HEATING_INEFFECTIVE = 9,
    HEATER_STUCK_ON = 10,
    FAN_FAILURE = 11,
    SESSION_TIME_LIMIT = 12,
    UNEXPECTED_RESET = 13,
    INTERNAL = 14,
};
enum class FanMode : uint8_t {
    AUTO = 0,
    ON = 1,
    OFF = 2,
};
enum class EndReason : uint8_t {
    NONE = 0,
    COMPLETED = 1,
    STOPPED_BY_USER = 2,
    STOPPED_ON_DEVICE = 3,
    ERROR = 4,
    OVER_TEMPERATURE = 5,
};
enum class Material : uint8_t {
    CUSTOM = 0,
    PLA = 1,
    PETG = 2,
    ABS = 3,
    ASA = 4,
    TPU = 5,
    PA = 6,
    PC = 7,
    PVA = 8,
    BVOH = 9,
    PEEK = 10,
    PEI = 11,
    PPS = 12,
    PA_CF = 13,
    PA_GF = 14,
    PETG_CF = 15,
    PLA_CF = 16,
    PC_CF = 17,
    ASA_CF = 18,
    PPS_CF = 19,
};

namespace StatusFlag {
constexpr uint8_t HEATER_RELAY = 1u << 0;
constexpr uint8_t HEATER_OUTPUT = 1u << 1;
constexpr uint8_t FAN_ON = 1u << 2;
constexpr uint8_t CLIENT_CONNECTED = 1u << 3;
constexpr uint8_t CHAMBER_SENSOR_OK = 1u << 4;
constexpr uint8_t HEATER_SENSOR_OK = 1u << 5;
constexpr uint8_t SESSION_ACTIVE = 1u << 6;
constexpr uint8_t TIME_SYNCED = 1u << 7;
}  // namespace StatusFlag
namespace Capability {
constexpr uint16_t HEATER_NTC = 1u << 0;
constexpr uint16_t FAN_TACH = 1u << 1;
constexpr uint16_t SAFETY_RELAY = 1u << 2;
constexpr uint16_t IDENTIFY_LED = 1u << 3;
constexpr uint16_t LOCAL_BUTTON = 1u << 4;
constexpr uint16_t OTA_BLE = 1u << 5;
}  // namespace Capability

constexpr int16_t kMinTargetCentiC = 3500;
constexpr int16_t kMaxTargetCentiC = 7000;
constexpr uint32_t kMinDurationSec = 900u;
constexpr uint32_t kMaxDurationSec = 172800u;
constexpr int16_t kInvalidTemperature = INT16_MIN;
constexpr uint16_t kInvalidHumidity = 65535u;
constexpr uint32_t kUnknownRemaining = 4294967295u;
constexpr uint8_t kMaterialCount = 20;

}  // namespace spooldry
