// Minimal Arduino-ESP32 3.3 API surface used by SpoolDry (signatures from cores/esp32 3.3.12).
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#define HIGH 0x1
#define LOW 0x0
#define INPUT 0x01
#define OUTPUT 0x03
#define INPUT_PULLUP 0x05
#define FALLING 0x02
#define IRAM_ATTR
typedef enum { ADC_0db, ADC_2_5db, ADC_6db, ADC_11db, ADC_ATTENDB_MAX } adc_attenuation_t;
uint32_t millis();
void delay(uint32_t);
void pinMode(uint8_t pin, uint8_t mode);
void digitalWrite(uint8_t pin, uint8_t val);
int digitalRead(uint8_t pin);
uint32_t analogReadMilliVolts(uint8_t pin);
void analogSetPinAttenuation(uint8_t pin, adc_attenuation_t attenuation);
bool ledcAttach(uint8_t pin, uint32_t freq, uint8_t resolution);
bool ledcWrite(uint8_t pin, uint32_t duty);
void rgbLedWrite(uint8_t pin, uint8_t red_val, uint8_t green_val, uint8_t blue_val);
void attachInterrupt(uint8_t pin, void (*)(void), int mode);
inline uint8_t digitalPinToInterrupt(uint8_t p) { return p; }
void noInterrupts();
void interrupts();
class String { public: String(const char* s = "") {(void)s;} };
class HardwareSerial { public: void begin(unsigned long); int printf(const char*, ...); size_t println(const char*); };
extern HardwareSerial Serial;
