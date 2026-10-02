#include "BleLink.h"

#include <NimBLEDevice.h>
#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

namespace spooldry {

namespace {
constexpr uint32_t kPairingWindowMs = 5UL * 60UL * 1000UL;

QueueHandle_t g_cmdQueue = nullptr;
NimBLEServer* g_server = nullptr;
NimBLECharacteristic* g_deviceInfo = nullptr;
NimBLECharacteristic* g_temperature = nullptr;
NimBLECharacteristic* g_humidity = nullptr;
NimBLECharacteristic* g_heaterState = nullptr;
NimBLECharacteristic* g_fanState = nullptr;
NimBLECharacteristic* g_session = nullptr;
NimBLECharacteristic* g_target = nullptr;
NimBLECharacteristic* g_remaining = nullptr;
NimBLECharacteristic* g_status = nullptr;
NimBLECharacteristic* g_command = nullptr;
NimBLECharacteristic* g_response = nullptr;
NimBLECharacteristic* g_firmware = nullptr;
volatile bool g_connected = false;
volatile uint32_t g_pairingOpenedMs = 0;
volatile bool g_pairingOpen = true;
volatile int g_bondsAtConnect = 0;
char g_name[32] = "SpoolDry";

bool pairingOpenNow() {
    return g_pairingOpen && (millis() - g_pairingOpenedMs) < kPairingWindowMs;
}

void restartAdvertising();

class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* server, NimBLEConnInfo& info) override {
        g_connected = true;
        g_bondsAtConnect = NimBLEDevice::getNumBonds();
        // Ask iOS for a comfortable connection interval (30-50 ms) and 4 s supervision timeout.
        server->updateConnParams(info.getConnHandle(), 24, 40, 0, 400);
    }
    void onDisconnect(NimBLEServer*, NimBLEConnInfo&, int) override {
        g_connected = false;  // the session keeps running: the ESP32 is the safety authority
        restartAdvertising();
    }
    void onAuthenticationComplete(NimBLEConnInfo& info) override {
        if (!info.isEncrypted()) {
            g_server->disconnect(info.getConnHandle());
            return;
        }
        // New bonds are only accepted while the pairing window is open (5 min after power-on or after
        // holding the BOOT button for 10 s). Already-paired phones can always reconnect.
        const bool newBond = NimBLEDevice::getNumBonds() > g_bondsAtConnect;
        if (newBond && !pairingOpenNow()) {
            NimBLEDevice::deleteBond(info.getIdAddress());
            g_server->disconnect(info.getConnHandle());
        }
    }
};

class CommandCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& info) override {
        if (!info.isEncrypted()) return;  // also enforced by WRITE_ENC
        NimBLEAttValue v = chr->getValue();
        RawCommand cmd;
        const size_t n = v.size() > sizeof(cmd.data) ? sizeof(cmd.data) : v.size();
        memcpy(cmd.data, v.data(), n);
        // Oversized frames are passed truncated with their real length lost -> mark as invalid length.
        cmd.len = v.size() > sizeof(cmd.data) ? 0xFF : static_cast<uint8_t>(n);
        if (g_cmdQueue) xQueueSend(g_cmdQueue, &cmd, 0);
    }
};

ServerCallbacks g_serverCallbacks;
CommandCallbacks g_commandCallbacks;

void restartAdvertising() {
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->stop();
    NimBLEAdvertisementData advData;
    advData.setFlags(BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP);
    advData.setCompleteServices(NimBLEUUID(kServiceUUID));
    NimBLEAdvertisementData scanData;
    scanData.setName(g_name);
    adv->setAdvertisementData(advData);
    adv->setScanResponseData(scanData);
    adv->enableScanResponse(true);
    adv->start();
}

NimBLECharacteristic* makeReadNotify(NimBLEService* svc, const char* uuid) {
    return svc->createCharacteristic(uuid, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
}
}  // namespace

void BleLink::begin(const char* deviceName, const DeviceInfo& info) {
    strncpy(g_name, deviceName, sizeof(g_name) - 1);
    g_name[sizeof(g_name) - 1] = '\0';
    g_cmdQueue = xQueueCreate(8, sizeof(RawCommand));
    g_pairingOpenedMs = millis();
    g_pairingOpen = true;

    NimBLEDevice::init(g_name);
    NimBLEDevice::setPower(9);  // dBm
    NimBLEDevice::setMTU(185);
    NimBLEDevice::setSecurityAuth(true, false, true);  // bonding, no MITM (no display/keypad), LE Secure Connections
    NimBLEDevice::setSecurityIOCap(BLE_HS_IO_NO_INPUT_OUTPUT);

    g_server = NimBLEDevice::createServer();
    g_server->setCallbacks(&g_serverCallbacks, false);

    NimBLEService* svc = g_server->createService(kServiceUUID);
    g_deviceInfo = svc->createCharacteristic(kCharDeviceInfoUUID, NIMBLE_PROPERTY::READ);
    g_temperature = makeReadNotify(svc, kCharTemperatureUUID);
    g_humidity = makeReadNotify(svc, kCharHumidityUUID);
    g_heaterState = makeReadNotify(svc, kCharHeaterStateUUID);
    g_fanState = makeReadNotify(svc, kCharFanStateUUID);
    g_session = makeReadNotify(svc, kCharDryingSessionUUID);
    g_target = makeReadNotify(svc, kCharTargetTempUUID);
    g_remaining = makeReadNotify(svc, kCharRemainingTimeUUID);
    g_status = makeReadNotify(svc, kCharDeviceStatusUUID);
    g_command = svc->createCharacteristic(kCharCommandUUID, NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_ENC);
    g_command->setCallbacks(&g_commandCallbacks);
    g_response = makeReadNotify(svc, kCharCommandResponseUUID);
    g_firmware = svc->createCharacteristic(kCharFirmwareVersionUUID, NIMBLE_PROPERTY::READ);
    g_firmware->setValue(kFirmwareVersionString);

    uint8_t buf[32];
    const size_t n = encodeDeviceInfo(info, buf, sizeof(buf));
    g_deviceInfo->setValue(buf, n);

    // Standard Device Information Service for generic BLE tools.
    NimBLEService* dis = g_server->createService("180A");
    dis->createCharacteristic("2A29", NIMBLE_PROPERTY::READ)->setValue("SpoolDry");
    dis->createCharacteristic("2A24", NIMBLE_PROPERTY::READ)->setValue("SpoolDry Controller HW1 (ESP32-C6)");
    dis->createCharacteristic("2A26", NIMBLE_PROPERTY::READ)->setValue(kFirmwareVersionString);
    dis->createCharacteristic("2A27", NIMBLE_PROPERTY::READ)->setValue("1");

    g_server->start();
    g_server->advertiseOnDisconnect(false);  // we restart advertising ourselves with our own payload
    restartAdvertising();
}

bool BleLink::popCommand(RawCommand& out) {
    return g_cmdQueue && xQueueReceive(g_cmdQueue, &out, 0) == pdTRUE;
}

void BleLink::sendResponse(const Response& r) {
    if (!g_response) return;
    uint8_t buf[kResponseHeaderSize + kMaxResponsePayload];
    const size_t n = encodeResponse(r, buf, sizeof(buf));
    g_response->setValue(buf, n);
    if (g_connected) g_response->notify();
}

void BleLink::publish(const Snapshot& s, bool notify) {
    if (!g_status) return;
    uint8_t buf[40];
    size_t n;
    struct Item {
        NimBLECharacteristic* chr;
        size_t (*enc)(const Snapshot&, uint8_t*, size_t);
    };
    const Item items[] = {
        {g_temperature, encodeTemperature}, {g_humidity, encodeHumidity},       {g_heaterState, encodeHeaterState},
        {g_fanState, encodeFanState},       {g_session, encodeDryingSession},   {g_target, encodeTargetTemp},
        {g_remaining, encodeRemainingTime}, {g_status, encodeDeviceStatus},
    };
    for (const Item& it : items) {
        n = it.enc(s, buf, sizeof(buf));
        if (n == 0) continue;
        it.chr->setValue(buf, n);
        if (notify && g_connected) it.chr->notify();
    }
}

void BleLink::setDeviceName(const char* name) {
    strncpy(g_name, name, sizeof(g_name) - 1);
    g_name[sizeof(g_name) - 1] = '\0';
    NimBLEDevice::setDeviceName(g_name);
    restartAdvertising();
}

bool BleLink::clientConnected() const { return g_connected; }

bool BleLink::pairingWindowOpen(uint32_t nowMs) const {
    (void)nowMs;
    return pairingOpenNow();
}

void BleLink::openPairingWindow(uint32_t nowMs) {
    g_pairingOpenedMs = nowMs;
    g_pairingOpen = true;
}

void BleLink::clearBonds() { NimBLEDevice::deleteAllBonds(); }

}  // namespace spooldry
