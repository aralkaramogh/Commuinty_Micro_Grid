// Minimal fake Arduino API so main.cpp can be compile-checked on a PC (g++).
// It does NOT emulate the ESP32; it only proves main.cpp is valid C++.
#pragma once
#include <stdint.h>
#include <stdio.h>
#define HIGH 1
#define LOW 0
#define OUTPUT 1
#define INPUT_PULLUP 2
inline void pinMode(int, int) {}
inline void digitalWrite(int, int) {}
inline int digitalRead(int) { return HIGH; }
inline unsigned long millis() { return 0; }
struct FakeSerial {
    void begin(long) {}
    void setRxBufferSize(int) {}
    int available() { return 0; }
    int read() { return -1; }
    void print(const char* s) { fputs(s, stdout); }
    void print(char c) { putchar(c); }
    void print(long v) { printf("%ld", v); }
    void print(int v) { printf("%d", v); }
    void print(unsigned v) { printf("%u", v); }
    void print(unsigned long v) { printf("%lu", v); }
    void print(double v, int d = 2) { printf("%.*f", d, v); }
    void println(const char* s) { puts(s); }
};
extern FakeSerial Serial;
