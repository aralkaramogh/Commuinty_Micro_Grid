// Compile-check harness for main.cpp (see arduino_stub/Arduino.h).
#include "Arduino.h"
FakeSerial Serial;
void setup(); void loop();
int main() { setup(); loop(); return 0; }
