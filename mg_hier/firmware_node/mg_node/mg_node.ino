// mg_node.ino - ONE sketch for every node ESP32 (H1, H2, CL, SB).
// MATLAB sends one line per tick; the line type decides the role:
//   "L,..." load node (house or community load)  -> reply "l,..."
//   "B,..." solar+BESS node                       -> reply "b,..."
//   "R"     reset (everything OFF)                -> "READY"
// LEDs  load node: A critical ON, B flexible ON, C comms lost (blink), D trip/lockout or E-stop
//       SB node  : A discharging, B charging, C comms lost (blink), D clamped/BESS fault or E-stop
// E-stop (pull-up, pressed = LOW): load node opens both relays; SB node stops the
// inverter (P = Q = 0). LATCHED: stays stopped after release until a reset ("R").
// Reported to the main controller as hstate 3 (load) / clamped 2 (SB).
// Every relay is OFF at power-up until the main controller sends "enable".
#include <Arduino.h>
#include "node.h"

static LoadSt ls; static SbSt bs;
static char line[256]; static size_t len = 0; static char reply[200];
static char role = '?'; static LoadOut lo; static SbOut so; static int bess_fault = 0;

static void leds(bool estop) {
    const bool blink = (millis() / 250) % 2;
    int a = 0, b = 0, c = 0, d = estop ? 1 : 0;
    if (role == 'L') { a = lo.tie; b = lo.flex; c = lo.comm_lost && blink; d = d || lo.hstate > 0; }   // hstate 3 = E-stop latched
    if (role == 'B') { a = so.p > 0; b = so.p < 0; c = so.comm_lost && blink; d = d || so.clamped || bess_fault; }
    digitalWrite(LED_A, (!estop && a) ? HIGH : LOW); digitalWrite(LED_B, (!estop && b) ? HIGH : LOW);
    digitalWrite(LED_C, c ? HIGH : LOW);             digitalWrite(LED_D, d ? HIGH : LOW);
}

static void reset_all() {
    load_init(ls); sb_init(bs); role = '?';
    lo.tie = lo.flex = lo.hstate = lo.strikes = lo.comm_lost = 0; lo.e_imp = lo.e_exp = 0;
    so.p = so.q = 0; so.sync = so.clamped = so.comm_lost = 0; bess_fault = 0;
}

void setup() {
    const int pins[4] = {LED_A, LED_B, LED_C, LED_D};
    for (int i = 0; i < 4; i++) { pinMode(pins[i], OUTPUT); digitalWrite(pins[i], LOW); }
    pinMode(ESTOP_PIN, INPUT_PULLUP);
    Serial.setRxBufferSize(1024);
    Serial.begin(SERIAL_BAUD);
    reset_all();
    Serial.println("READY");
}

void loop() {
    const bool estop = digitalRead(ESTOP_PIN) == LOW;
    leds(estop);
    while (Serial.available()) {
        char ch = (char)Serial.read();
        if (ch == '\r') continue;
        if (ch != '\n') { if (len < sizeof(line) - 1) line[len++] = ch; continue; }
        line[len] = '\0'; len = 0;
        if (line[0] == 'R') { reset_all(); Serial.println("READY"); continue; }
        if (line[0] == 'L') {
            LoadIn x;
            if (!parse_L(line, x)) { Serial.println("E,parse"); continue; }
            role = 'L'; load_step(ls, x, lo, estop);
            format_l(reply, sizeof reply, x, lo);
        } else if (line[0] == 'B') {
            SbIn x;
            if (!parse_B(line, x)) { Serial.println("E,parse"); continue; }
            role = 'B'; sb_step(bs, x, so, estop); bess_fault = x.bess_status;
            format_b(reply, sizeof reply, x, so);
        } else { Serial.println("E,unknown"); continue; }
        Serial.println(reply);
    }
}
