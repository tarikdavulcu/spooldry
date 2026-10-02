// Pure sensor math: Sensirion SHT4x frame decoding (with CRC) and NTC thermistor conversion.
#pragma once
#include <math.h>
#include <stddef.h>
#include <stdint.h>

#include "Config.h"
#include "ProtocolConstants.h"

namespace spooldry {

// SHT4x command: measure T & RH with high repeatability (max 8.3 ms).
constexpr uint8_t kSht4xAddress = 0x44;
constexpr uint8_t kSht4xMeasureHighPrecision = 0xFD;
constexpr uint8_t kSht4xSoftReset = 0x94;
constexpr uint8_t kSht4xReadSerial = 0x89;

// CRC-8, polynomial 0x31, init 0xFF (Sensirion datasheet section 4.4).
inline uint8_t sht4xCrc(const uint8_t* data, size_t len) {
    uint8_t crc = 0xFF;
    for (size_t i = 0; i < len; ++i) {
        crc ^= data[i];
        for (int b = 0; b < 8; ++b) crc = (crc & 0x80) ? static_cast<uint8_t>((crc << 1) ^ 0x31) : static_cast<uint8_t>(crc << 1);
    }
    return crc;
}

struct ClimateReading {
    bool valid = false;
    ErrorCode fault = ErrorCode::NONE;
    float temperatureC = NAN;
    float humidityRh = NAN;
};

// Decodes the 6-byte SHT4x measurement frame [T_msb, T_lsb, CRC, RH_msb, RH_lsb, CRC].
inline ClimateReading decodeSht4x(const uint8_t* frame, size_t len) {
    ClimateReading r;
    if (frame == nullptr || len != 6) {
        r.fault = ErrorCode::SENSOR_I2C;
        return r;
    }
    if (sht4xCrc(frame, 2) != frame[2] || sht4xCrc(frame + 3, 2) != frame[5]) {
        r.fault = ErrorCode::SENSOR_CRC;
        return r;
    }
    const uint16_t tRaw = static_cast<uint16_t>((frame[0] << 8) | frame[1]);
    const uint16_t hRaw = static_cast<uint16_t>((frame[3] << 8) | frame[4]);
    const float t = -45.0f + 175.0f * static_cast<float>(tRaw) / 65535.0f;
    float h = -6.0f + 125.0f * static_cast<float>(hRaw) / 65535.0f;
    // Datasheet: values outside 0..100 %RH are physically impossible; clamp small excursions.
    if (h < 0.0f) h = 0.0f;
    if (h > 100.0f) h = 100.0f;
    if (t < limits::kChamberMinPlausibleC || t > limits::kChamberMaxPlausibleC) {
        r.fault = ErrorCode::SENSOR_RANGE;
        r.temperatureC = t;
        return r;
    }
    // An all-zero or all-0xFF raw word with valid CRC is a classic stuck-bus pattern.
    if ((tRaw == 0x0000 && hRaw == 0x0000) || (tRaw == 0xFFFF && hRaw == 0xFFFF)) {
        r.fault = ErrorCode::SENSOR_RANGE;
        return r;
    }
    r.valid = true;
    r.temperatureC = t;
    r.humidityRh = h;
    return r;
}

struct NtcReading {
    bool valid = false;
    ErrorCode fault = ErrorCode::NONE;
    float temperatureC = NAN;
};

// Converts a divider voltage (NTC to GND, series resistor to supply) into degrees C.
inline NtcReading ntcFromMillivolts(float mv) {
    NtcReading r;
    if (mv >= ntc::kOpenAboveMv) {  // practically open circuit
        r.fault = ErrorCode::NTC_OPEN;
        return r;
    }
    if (mv <= ntc::kShortBelowMv) {  // short to ground
        r.fault = ErrorCode::NTC_SHORT;
        return r;
    }
    const float rNtc = ntc::kSeriesOhms * mv / (ntc::kSupplyMv - mv);
    const float invT = 1.0f / 298.15f + logf(rNtc / ntc::kR25Ohms) / ntc::kBeta;
    const float t = 1.0f / invT - 273.15f;
    if (t < -30.0f) {
        r.fault = ErrorCode::NTC_OPEN;
        return r;
    }
    if (t > 250.0f) {
        r.fault = ErrorCode::NTC_SHORT;
        return r;
    }
    r.valid = true;
    r.temperatureC = t;
    return r;
}

// Inverse of ntcFromMillivolts (used by tests and the simulator).
inline float ntcMillivoltsForTemp(float tC) {
    const float t = tC + 273.15f;
    const float r = ntc::kR25Ohms * expf(ntc::kBeta * (1.0f / t - 1.0f / 298.15f));
    return ntc::kSupplyMv * r / (r + ntc::kSeriesOhms);
}

}  // namespace spooldry
