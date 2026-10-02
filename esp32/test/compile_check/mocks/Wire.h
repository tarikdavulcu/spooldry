#pragma once
#include <stdint.h>
#include <stddef.h>
class TwoWire { public:
  bool begin(int sda, int scl, uint32_t frequency = 0);
  bool end();
  void setTimeOut(uint16_t timeOutMillis);
  void beginTransmission(uint8_t address);
  uint8_t endTransmission(bool sendStop = true);
  size_t write(uint8_t);
  uint8_t requestFrom(uint8_t address, uint8_t size);
  int available();
  int read();
};
extern TwoWire Wire;
