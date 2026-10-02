/*
 * SpoolDry firmware 1.0.0 - BLE filament dryer controller
 * Board:  Espressif ESP32-C6-DevKitC-1-N8 (Arduino-ESP32 core 3.3.x)
 * Libs:   NimBLE-Arduino 2.5.x (h2zero). No other third-party libraries.
 *
 * Safety model (see docs/SAFETY.md):
 *   - Heater, relay and fan gates have hardware pull-downs and are driven LOW first thing in setup().
 *   - The ESP32 runs the session autonomously and enforces every limit; BLE disconnects do not matter.
 *   - Task watchdog (5 s). A hang resets the chip; GPIOs fall back to their pull-downs (heater OFF);
 *     sessions are never resumed after a reset.
 *   - Independent hardware: 85 C bimetal thermostat in the relay-coil circuit, 100 C one-shot thermal
 *     cutoff in the heater current path, self-limiting PTC element, 7.5 A fuse.
 */
#include <Arduino.h>
#include <Preferences.h>

#include "esp_task_wdt.h"
#include "src/core/Config.h"
#include "src/core/DryerController.h"
#include "src/core/Protocol.h"
#include "src/hal/BleLink.h"
#include "src/hal/Hardware.h"

using namespace spooldry;

static Hardware g_hw;
static BleLink g_ble;
static DryerController g_ctl;
static Preferences g_prefs;

static uint32_t g_lastTickMs = 0;
static uint32_t g_lastNotifyMs = 0;
static uint32_t g_savedSessionCounter = 0;
static uint8_t g_savedFault = 0;
static DeviceState g_lastState = DeviceState::IDLE;
static ControllerOutputs g_out;

static void setupWatchdog() {
    esp_task_wdt_config_t cfg = {};
    cfg.timeout_ms = limits::kTaskWatchdogMs;
    cfg.idle_core_mask = 0;
    cfg.trigger_panic = true;  // reset the chip instead of only logging
    if (esp_task_wdt_reconfigure(&cfg) != ESP_OK) {
        esp_task_wdt_init(&cfg);
    }
    esp_task_wdt_add(NULL);  // supervise the Arduino loop task
}

static void defaultName(char* out, size_t cap) {
    uint8_t id[6];
    Hardware::deviceId(id);
    snprintf(out, cap, "%s%02X%02X", kAdvertisedNamePrefix, id[4], id[5]);
}

static void persistIfChanged() {
    const uint32_t counter = g_ctl.sessionCounter();
    if (counter != g_savedSessionCounter) {
        g_prefs.putUInt("sessions", counter);
        g_savedSessionCounter = counter;
    }
    const uint8_t fault = static_cast<uint8_t>(g_ctl.lastLatchedFault());
    if (fault != g_savedFault) {
        g_prefs.putUChar("lastFault", fault);
        g_savedFault = fault;
    }
}

static void handleCommands(uint32_t now) {
    RawCommand raw;
    while (g_ble.popCommand(raw)) {
        Command cmd;
        ResultCode rc;
        Response resp;
        if (raw.len == 0xFF || !decodeCommand(raw.data, raw.len, cmd, rc)) {
            const uint8_t seq = raw.len >= 3 && raw.len != 0xFF ? raw.data[2] : 0;
            const uint8_t op = raw.len >= 2 && raw.len != 0xFF ? raw.data[1] : 0;
            resp = DryerController::nack(seq, op, raw.len == 0xFF ? ResultCode::BAD_LENGTH : rc);
        } else {
            resp = g_ctl.handleCommand(cmd, now);
        }
        g_ble.sendResponse(resp);
        Serial.printf("[cmd] op=%u seq=%u -> %s result=%u\n", resp.opcode, resp.seq,
                      resp.type == ResponseType::ACK ? "ACK" : "NACK", static_cast<unsigned>(resp.result));
    }
    char name[kMaxDeviceNameLen + 1];
    if (g_ctl.takePendingName(name, sizeof(name))) {
        g_prefs.putString("name", name);
        g_ble.setDeviceName(name);
    }
}

void setup() {
    // 1. Outputs safe before anything else (pull-downs already hold them low in hardware).
    hardwareSafeState();
    Serial.begin(115200);
    delay(50);

    const ResetCause cause = Hardware::resetCause();
    g_prefs.begin("spooldry", false);
    g_savedSessionCounter = g_prefs.getUInt("sessions", 0);
    g_savedFault = g_prefs.getUChar("lastFault", 0);

    char name[kMaxDeviceNameLen + 1];
    if (g_prefs.getString("name", name, sizeof(name)) == 0) defaultName(name, sizeof(name));

    g_hw.begin();
    g_ctl.begin(millis(), cause, g_savedSessionCounter, static_cast<ErrorCode>(g_savedFault));
    persistIfChanged();

    DeviceInfo info;
    Hardware::deviceId(info.deviceId);
    info.capabilities = g_ctl.capabilities();
    info.resetReason = static_cast<uint8_t>(cause);
    info.lastFault = g_savedFault;
    g_ble.begin(name, info);

    setupWatchdog();
    Serial.printf("\nSpoolDry firmware %s (BLE protocol v%u) ready as \"%s\"\n", kFirmwareVersionString, kProtocolVersion, name);
    Serial.printf("Reset cause: %u, last fault: %s, sessions so far: %lu\n", static_cast<unsigned>(cause),
                  errorName(static_cast<ErrorCode>(g_savedFault)), static_cast<unsigned long>(g_savedSessionCounter));
    Serial.println("Advertising SpoolDry service 5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44");
}

void loop() {
    const uint32_t now = millis();
    const ClimateReading& climate = g_hw.pollClimate(now);  // non-blocking

    switch (g_hw.pollButton(now)) {
        case Hardware::ButtonEvent::SHORT_PRESS: g_ctl.localStop(now); break;
        case Hardware::ButtonEvent::LONG_PRESS_3S: g_ctl.localReset(now); break;
        case Hardware::ButtonEvent::LONG_PRESS_10S:
            g_ble.clearBonds();
            g_ble.openPairingWindow(now);
            Serial.println("[ble] bonds cleared, pairing window open for 5 minutes");
            break;
        default: break;
    }

    handleCommands(now);

    if (now - g_lastTickMs >= control::kTickMs) {
        g_lastTickMs = now;
        g_ctl.setClientConnected(g_ble.clientConnected());
        ControllerInputs in;
        in.nowMs = now;
        in.chamber = climate;
        in.heater = g_hw.readHeaterNtc();
        in.fanRpm = g_hw.fanRpm(now);
        g_out = g_ctl.update(in);
        g_hw.apply(g_out);

        const Snapshot& s = g_ctl.snapshot();
        g_hw.showStatus(s, g_out.identify, g_ble.pairingWindowOpen(now), now);
        const bool stateChanged = s.state != g_lastState;
        // Notify on every state change immediately, otherwise once per second.
        const bool notify = stateChanged || (now - g_lastNotifyMs) >= 1000;
        g_ble.publish(s, notify);
        if (notify) g_lastNotifyMs = now;
        if (stateChanged) {
            Serial.printf("[state] %s -> %s (error %s)\n", stateName(g_lastState), stateName(s.state), errorName(s.error));
            g_lastState = s.state;
        }
        persistIfChanged();
    }

    esp_task_wdt_reset();
    delay(5);
}
