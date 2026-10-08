// LiquidCrystal_I2C stub for a host compile check: prints what the LCD would show
#pragma once
#include <stdint.h>
#include <stdio.h>
struct LiquidCrystal_I2C {
    int row = 0;
    LiquidCrystal_I2C(uint8_t, int, int) {}
    void init() {} void backlight() {}
    void setCursor(int, int r) { row = r; }
    void print(const char* s) { printf("LCD%d|%s|\n", row, s); }
};
