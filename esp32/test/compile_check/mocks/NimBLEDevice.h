// Subset of NimBLE-Arduino 2.5.1 public API (signatures copied from the 2.5.1 headers).
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string>
#define BLE_HS_ADV_F_DISC_GEN 0x02
#define BLE_HS_ADV_F_BREDR_UNSUP 0x04
#define BLE_HS_IO_NO_INPUT_OUTPUT 0x03
#define BLE_HS_CONN_HANDLE_NONE 0xffff
#define BLE_ERR_REM_USER_CONN_TERM 0x13
typedef enum { READ = 0x0002, READ_ENC = 0x0004, WRITE = 0x0008, WRITE_ENC = 0x0020, NOTIFY = 0x0010 } NIMBLE_PROPERTY_E;
namespace NIMBLE_PROPERTY { enum : uint16_t { READ = 0x0002, READ_ENC = 0x0004, NOTIFY = 0x0010, WRITE = 0x0008, WRITE_ENC = 0x0020 }; }
class NimBLEAddress { public: std::string toString() const; const uint8_t* getVal() const; };
class NimBLEUUID { public: NimBLEUUID(const char* s); };
class NimBLEConnInfo { public:
  NimBLEAddress getAddress() const; NimBLEAddress getIdAddress() const; uint16_t getConnHandle() const;
  bool isBonded() const; bool isEncrypted() const; bool isAuthenticated() const; };
class NimBLEAttValue { public: uint16_t size() const; uint16_t length() const; const uint8_t* data() const; };
class NimBLECharacteristic;
class NimBLECharacteristicCallbacks { public: virtual ~NimBLECharacteristicCallbacks() {}
  virtual void onRead(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo);
  virtual void onWrite(NimBLECharacteristic* pCharacteristic, NimBLEConnInfo& connInfo); };
class NimBLECharacteristic { public:
  void setCallbacks(NimBLECharacteristicCallbacks* pCallbacks);
  bool notify(uint16_t connHandle = BLE_HS_CONN_HANDLE_NONE) const;
  void setValue(const uint8_t* data, size_t size);
  void setValue(const char* str);
  NimBLEAttValue getValue() const; };
class NimBLEService { public:
  NimBLECharacteristic* createCharacteristic(const char* uuid, uint32_t properties = NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE, uint16_t max_len = 512); };
class NimBLEServer;
class NimBLEServerCallbacks { public: virtual ~NimBLEServerCallbacks() {}
  virtual void onConnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo);
  virtual void onDisconnect(NimBLEServer* pServer, NimBLEConnInfo& connInfo, int reason);
  virtual void onAuthenticationComplete(NimBLEConnInfo& connInfo); };
class NimBLEServer { public:
  bool start(); uint8_t getConnectedCount() const;
  bool disconnect(uint16_t connHandle, uint8_t reason = BLE_ERR_REM_USER_CONN_TERM) const;
  void setCallbacks(NimBLEServerCallbacks* pCallbacks, bool deleteCallbacks = true);
  NimBLEService* createService(const char* uuid);
  void advertiseOnDisconnect(bool enable);
  void updateConnParams(uint16_t connHandle, uint16_t minInterval, uint16_t maxInterval, uint16_t latency, uint16_t timeout) const; };
class NimBLEAdvertisementData { public:
  bool setFlags(uint8_t flag); bool setCompleteServices(const NimBLEUUID& uuid); bool setName(const std::string& name, bool isComplete = true); };
class NimBLEAdvertising { public:
  bool start(uint32_t duration = 0, const NimBLEAddress* dirAddr = nullptr); bool stop();
  void enableScanResponse(bool enable);
  bool setAdvertisementData(const NimBLEAdvertisementData& advertisementData);
  bool setScanResponseData(const NimBLEAdvertisementData& advertisementData); };
class NimBLEDevice { public:
  static bool init(const std::string& deviceName);
  static bool setDeviceName(const std::string& deviceName);
  static void setSecurityAuth(bool bonding, bool mitm, bool sc);
  static void setSecurityIOCap(uint8_t iocap);
  static bool setMTU(uint16_t mtu);
  static bool setPower(int8_t dbm);
  static NimBLEServer* createServer();
  static NimBLEAdvertising* getAdvertising();
  static bool deleteBond(const NimBLEAddress& address);
  static int getNumBonds();
  static bool deleteAllBonds(); };
