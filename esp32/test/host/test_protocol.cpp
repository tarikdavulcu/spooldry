// Protocol codec + sensor math tests.
#include <cstring>

#include "../../SpoolDry/src/core/Bytes.h"
#include "../../SpoolDry/src/core/Protocol.h"
#include "../../SpoolDry/src/core/Sensors.h"
#include "TestFramework.h"

using namespace spooldry;

static size_t frame(Opcode op, uint8_t seq, std::initializer_list<uint8_t> payload, uint8_t* out) {
    uint8_t p[40];
    uint8_t n = 0;
    for (uint8_t b : payload) p[n++] = b;
    return encodeCommandFrame(op, seq, p, n, out, 64);
}

TEST(decode_start_session_valid) {
    // material PA_CF(13), 70.00 C = 7000 = 0x1B58, 8 h = 28800 = 0x00007080, unix 0x6AB00000, fan AUTO
    uint8_t f[64];
    size_t n = frame(Opcode::START_SESSION, 7, {13, 0x58, 0x1B, 0x80, 0x70, 0x00, 0x00, 0x00, 0x00, 0xB0, 0x6A, 0}, f);
    CHECK_EQ(n, 16u);
    Command c;
    ResultCode rc;
    CHECK(decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::OK);
    CHECK_EQ(c.seq, 7);
    CHECK_EQ((int)c.material, (int)Material::PA_CF);
    CHECK_EQ(c.targetCentiC, 7000);
    CHECK_EQ(c.durationSec, 28800u);
    CHECK_EQ(c.unixTime, 0x6AB00000u);
    CHECK_EQ((int)c.fanMode, (int)FanMode::AUTO);
}

TEST(decode_rejects_bad_version_length_opcode) {
    uint8_t f[64];
    size_t n = frame(Opcode::REQUEST_STATUS, 1, {}, f);
    Command c;
    ResultCode rc;
    f[0] = 2;
    CHECK(!decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::UNSUPPORTED_VERSION);
    f[0] = 1;
    CHECK(!decodeCommand(f, n + 1, c, rc));  // trailing garbage
    CHECK_EQ((int)rc, (int)ResultCode::BAD_LENGTH);
    CHECK(!decodeCommand(f, 2, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::BAD_LENGTH);
    f[1] = 0x55;
    CHECK(!decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::UNKNOWN_OPCODE);
    CHECK_EQ(c.seq, 1);  // seq still available for NACK matching
    CHECK(!decodeCommand(nullptr, 0, c, rc));
    // Wrong payload size for SET_TARGET_TEMP
    n = frame(Opcode::SET_TARGET_TEMP, 3, {0x10}, f);
    CHECK(!decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::BAD_LENGTH);
}

TEST(decode_rejects_out_of_range_parameters) {
    uint8_t f[64];
    Command c;
    ResultCode rc;
    // 90 C exceeds hardware max 70 C
    size_t n = frame(Opcode::SET_TARGET_TEMP, 1, {0x28, 0x23}, f);
    CHECK(!decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::INVALID_PARAMETER);
    // 60 s duration < 15 min minimum
    n = frame(Opcode::SET_DURATION, 1, {60, 0, 0, 0}, f);
    CHECK(!decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::INVALID_PARAMETER);
    n = frame(Opcode::SET_FILAMENT, 1, {99}, f);
    CHECK(!decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::INVALID_PARAMETER);
    n = frame(Opcode::SET_FAN_MODE, 1, {7}, f);
    CHECK(!decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::INVALID_PARAMETER);
    // Device name with control character
    n = frame(Opcode::SET_DEVICE_NAME, 1, {'A', 0x01}, f);
    CHECK(!decodeCommand(f, n, c, rc));
    CHECK_EQ((int)rc, (int)ResultCode::INVALID_PARAMETER);
    n = frame(Opcode::SET_DEVICE_NAME, 1, {'L', 'a', 'b', ' ', '2'}, f);
    CHECK(decodeCommand(f, n, c, rc));
    CHECK(std::strcmp(c.name, "Lab 2") == 0);
}

TEST(encode_sizes_match_spec) {
    uint8_t buf[64];
    Snapshot s;
    DeviceInfo info;
    CHECK_EQ(encodeDeviceStatus(s, buf, sizeof(buf)), (size_t)kSizeDeviceStatus);
    CHECK_EQ(encodeDeviceInfo(info, buf, sizeof(buf)), (size_t)kSizeDeviceInfo);
    CHECK_EQ(encodeTemperature(s, buf, sizeof(buf)), (size_t)kSizeTemperature);
    CHECK_EQ(encodeHumidity(s, buf, sizeof(buf)), (size_t)kSizeHumidity);
    CHECK_EQ(encodeHeaterState(s, buf, sizeof(buf)), (size_t)kSizeHeaterState);
    CHECK_EQ(encodeFanState(s, buf, sizeof(buf)), (size_t)kSizeFanState);
    CHECK_EQ(encodeDryingSession(s, buf, sizeof(buf)), (size_t)kSizeDryingSession);
    CHECK_EQ(encodeTargetTemp(s, buf, sizeof(buf)), (size_t)kSizeTargetTemp);
    CHECK_EQ(encodeRemainingTime(s, buf, sizeof(buf)), (size_t)kSizeRemainingTime);
    Response r;
    r.payloadLen = 8;
    CHECK_EQ(encodeResponse(r, buf, sizeof(buf)), (size_t)14);
    CHECK(encodeResponse(r, buf, 14) == 14);
    CHECK_EQ(encodeDeviceStatus(s, buf, 10), (size_t)0);  // overflow detected, not truncated silently
}

TEST(encode_device_status_layout) {
    Snapshot s;
    s.state = DeviceState::DRYING;
    s.error = ErrorCode::NONE;
    s.flags = StatusFlag::HEATER_RELAY | StatusFlag::FAN_ON;
    s.chamberCentiC = 6720;
    s.humidityCentiRh = 1840;
    s.heaterCentiC = 7105;
    s.targetCentiC = 7000;
    s.remainingSec = 9660;
    s.elapsedDryingSec = 19140;
    s.sessionId = 42;
    s.material = Material::PA_CF;
    s.heaterDuty = 37;
    s.fanRpm = 6800;
    s.uptimeSec = 23456;
    s.fanMode = FanMode::AUTO;
    s.endReason = EndReason::NONE;
    s.statusSeq = 513;
    uint8_t b[36];
    CHECK_EQ(encodeDeviceStatus(s, b, sizeof(b)), (size_t)36);
    CHECK_EQ(b[0], 1);
    CHECK_EQ(b[1], 5);
    CHECK_EQ(b[3], 0x05);
    CHECK_EQ(b[4] | (b[5] << 8), 6720);
    CHECK_EQ(b[6] | (b[7] << 8), 1840);
    CHECK_EQ(b[10] | (b[11] << 8), 7000);
    CHECK_EQ(b[12] | (b[13] << 8) | (b[14] << 16) | (b[15] << 24), 9660);
    CHECK_EQ(b[24], 13);
    CHECK_EQ(b[25], 37);
    CHECK_EQ(b[26] | (b[27] << 8), 6800);
    CHECK_EQ(b[34] | (b[35] << 8), 513);
}

TEST(fixed_point_conversions) {
    CHECK_EQ(toCentiC(48.2f, true), 4820);
    CHECK_EQ(toCentiC(-5.555f, true), -556);
    CHECK_EQ(toCentiC(20.0f, false), kInvalidTemperature);
    CHECK_EQ(toCentiRh(18.4f, true), 1840);
    CHECK_EQ(toCentiRh(120.0f, true), 10000);
    CHECK_EQ(toCentiRh(-3.0f, true), 0);
    CHECK_EQ(toCentiRh(10.0f, false), kInvalidHumidity);
    CHECK_NEAR(fromCentiC(7000), 70.0, 1e-6);
}

TEST(sht4x_crc_datasheet_vector) {
    // Sensirion datasheet example: CRC(0xBEEF) = 0x92
    const uint8_t d[2] = {0xBE, 0xEF};
    CHECK_EQ(sht4xCrc(d, 2), 0x92);
}

TEST(sht4x_decode_valid_crc_error_and_range) {
    // T raw 0x6666 -> -45 + 175*26214/65535 = 25.0 C ; RH raw 0x8000 -> 56.5 %
    uint8_t f[6] = {0x66, 0x66, 0, 0x80, 0x00, 0};
    f[2] = sht4xCrc(f, 2);
    f[5] = sht4xCrc(f + 3, 2);
    ClimateReading r = decodeSht4x(f, 6);
    CHECK(r.valid);
    CHECK_NEAR(r.temperatureC, 25.0, 0.01);
    CHECK_NEAR(r.humidityRh, 56.5, 0.01);
    f[5] ^= 1;
    r = decodeSht4x(f, 6);
    CHECK(!r.valid);
    CHECK_EQ((int)r.fault, (int)ErrorCode::SENSOR_CRC);
    // 0xFFFF temperature = 130 C -> out of plausible range
    uint8_t g[6] = {0xFF, 0xFF, 0, 0x80, 0x00, 0};
    g[2] = sht4xCrc(g, 2);
    g[5] = sht4xCrc(g + 3, 2);
    r = decodeSht4x(g, 6);
    CHECK(!r.valid);
    CHECK_EQ((int)r.fault, (int)ErrorCode::SENSOR_RANGE);
    r = decodeSht4x(g, 5);
    CHECK_EQ((int)r.fault, (int)ErrorCode::SENSOR_I2C);
}

TEST(ntc_roundtrip_open_short) {
    for (float t = 0.0f; t <= 200.0f; t += 10.0f) {
        NtcReading r = ntcFromMillivolts(ntcMillivoltsForTemp(t));
        CHECK(r.valid);
        CHECK_NEAR(r.temperatureC, t, 0.05);
    }
    CHECK_EQ((int)ntcFromMillivolts(3299.0f).fault, (int)ErrorCode::NTC_OPEN);
    CHECK_EQ((int)ntcFromMillivolts(1.0f).fault, (int)ErrorCode::NTC_SHORT);
    // Mid-scale at the operating range (good ADC resolution).
    CHECK(ntcMillivoltsForTemp(25.0f) > 2000.0f && ntcMillivoltsForTemp(25.0f) < 2600.0f);
    CHECK(ntcMillivoltsForTemp(70.0f) > 600.0f && ntcMillivoltsForTemp(70.0f) < 1200.0f);
}
