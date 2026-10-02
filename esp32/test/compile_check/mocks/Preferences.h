#pragma once
#include <stdint.h>
#include <stddef.h>
class Preferences { public:
  bool begin(const char *name, bool readOnly = false, const char *partition_label = NULL);
  size_t putUChar(const char *key, uint8_t value);
  size_t putUInt(const char *key, uint32_t value);
  size_t putString(const char *key, const char *value);
  uint8_t getUChar(const char *key, uint8_t defaultValue = 0);
  uint32_t getUInt(const char *key, uint32_t defaultValue = 0);
  size_t getString(const char *key, char *value, size_t maxLen);
};
