// SpoolDry GATT server (NimBLE-Arduino 2.x). Exposes the BLE Protocol v1 service and queues
// command writes for the main loop. BLE callbacks never touch outputs directly.
#pragma once
#include <Arduino.h>

#include "../core/Protocol.h"

namespace spooldry {

struct RawCommand {
    uint8_t len = 0;
    uint8_t data[kCommandHeaderSize + kMaxCommandPayload] = {0};
};

class BleLink {
public:
    void begin(const char* deviceName, const DeviceInfo& info);
    bool popCommand(RawCommand& out);
    void sendResponse(const Response& r);
    // Updates every characteristic value; notifies subscribers when `notify` is true.
    void publish(const Snapshot& s, bool notify);
    void setDeviceName(const char* name);
    bool clientConnected() const;
    bool pairingWindowOpen(uint32_t nowMs) const;
    void openPairingWindow(uint32_t nowMs);
    void clearBonds();
};

}  // namespace spooldry
