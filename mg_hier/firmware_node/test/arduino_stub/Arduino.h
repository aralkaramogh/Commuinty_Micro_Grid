// Minimal Arduino stub for a host compile check (not a simulator).
#pragma once
#include <stddef.h>
#include <stdint.h>
#include <math.h>
#include <stdio.h>
#define HIGH 1
#define LOW 0
#define OUTPUT 1
#define INPUT_PULLUP 2
inline void pinMode(int, int) {}
inline void digitalWrite(int, int) {}
inline int digitalRead(int) { return HIGH; }
inline unsigned long millis() { return 0; }
struct SerialStub {
    void begin(long) {} void setRxBufferSize(size_t) {}
    int available() { return 0; } int read() { return -1; }
    void println(const char*) {} void print(const char*) {}
};
static SerialStub Serial;
