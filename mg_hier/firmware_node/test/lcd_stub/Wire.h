// Wire stub for a host compile check only
#pragma once
#include <stdint.h>
struct TwoWire { void begin(int, int) {} void beginTransmission(uint8_t) {} int endTransmission() { return 0; } };
static TwoWire Wire;
