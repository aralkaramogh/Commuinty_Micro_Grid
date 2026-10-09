// mg_node_lcd.ino - the SAME node controller as mg_node.ino (identical replies, same
// node.cpp), plus a 16x2 I2C LCD (PCF8574 backpack) that shows this node's values.
// Use it only on boards that have an LCD; mg_node.ino stays the reference sketch.
//
// Line 1 = parameter (with node id), line 2 = value + unit. Pages rotate every 2.5 s.
//   H1/H2 : Supply, Demand kW, Solar kW, Net power (import/export kW), Flexible load
//   CL    : Supply, Critical load, Flexible load (pump), Protection
//   SB    : Supply, Total demand kW, Solar kW, Battery status, SOC %, Battery V, Battery A
// MATLAB sends a "D,seq,mode,total_demand_w,role" line before each L/B line to boards
// listed in LCD_NODES (mode/total demand are not in the L/B lines). No reply to D.
//
// Wiring (I2C, chosen on the SAME header side as the LEDs):
//   ESP32-WROOM DevKit: SDA = GPIO 32, SCL = GPIO 13   (LEDs 25/26/27/14, E-stop 33)
//   ESP32-S3 DevKitC  : SDA = GPIO 16, SCL = GPIO 17   (LEDs 4/5/6/7, E-stop 15)
//   LCD backpack VCC = 5 V, GND = GND. SAFETY: most backpacks pull SDA/SCL up to VCC
//   (5 V) and ESP32 pins are 3.3 V. Use a level shifter, or remove the backpack's
//   pull-up resistors and add 4.7 k to 3.3 V. Do NOT use GPIO 12 (boot strap pin).
// Library: "LiquidCrystal I2C" (Frank de Brabander), Arduino Library Manager.
// LCD address: tries 0x27, then 0x3F.
#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include "node.h"

#if defined(CONFIG_IDF_TARGET_ESP32S3)
#define LCD_SDA 16
#define LCD_SCL 17
#else
#define LCD_SDA 32
#define LCD_SCL 13
#endif
#define PAGE_MS   2500
#define REFRESH_MS 400

static LoadSt ls; static SbSt bs;
static char line[256]; static size_t len = 0; static char reply[200];
static char role = '?'; static LoadOut lo; static SbOut so; static int bess_fault = 0;
// MATLAB-link watchdog (display only, node core untouched): no line for LINK_TIMEOUT_MS ->
// LED C blinks fast and the LCD says so, instead of freezing on the last state.
#define LINK_TIMEOUT_MS 3000UL
static unsigned long t_rx = 0;
static bool soft_estop = false;     // 'S,1' / 'S,0' from MATLAB = panel E-stop button (same as the pin)
static double sb_p_meas = 0;        // measured battery power (+ discharge) for the SB LEDs
static bool link_lost() { return role != '?' && (millis() - t_rx) > LINK_TIMEOUT_MS; }
static LoadIn li; static SbIn si;                       // last meter values (for the display)
static int d_mode = -1, d_role = 0; static double d_total = 0;   // from the D line
static LiquidCrystal_I2C* lcd = nullptr;
static unsigned long t_page = 0, t_ref = 0; static int page = 0;
static const char* NODE_NAME[5] = {"NODE", "H1", "H2", "CL", "SB"};

static void leds(bool estop) {
    const bool blink = (millis() / 250) % 2;
    int a = 0, b = 0, c = 0, d = estop ? 1 : 0;
    if (role == 'L') { a = lo.tie; b = lo.flex; c = lo.comm_lost && blink; d = d || lo.hstate > 0; }
    if (role == 'B') { a = sb_p_meas > 50; b = sb_p_meas < -50; c = so.comm_lost && blink; d = d || so.clamped || bess_fault; }
    if (link_lost()) c = (millis() / 100) % 2;          // fast blink = MATLAB script stopped
    digitalWrite(LED_A, (!estop && a) ? HIGH : LOW); digitalWrite(LED_B, (!estop && b) ? HIGH : LOW);
    digitalWrite(LED_C, c ? HIGH : LOW);             digitalWrite(LED_D, d ? HIGH : LOW);
}

static void reset_all() {
    load_init(ls); sb_init(bs); role = '?';
    lo.tie = lo.flex = lo.hstate = lo.strikes = lo.comm_lost = 0; lo.e_imp = lo.e_exp = 0;
    so.p = so.q = 0; so.sync = so.clamped = so.comm_lost = 0; bess_fault = 0;
    li.v = li.p_load = li.p_pv = 0; si.v_c = si.soc = si.p_bess = si.p_cpv = 0; si.bess_status = 0;
    d_mode = -1; d_role = 0; d_total = 0;
}

// ---------- display ----------
static void show(const char* l1, const char* l2) {
    if (!lcd) return;
    char a[17], b[17];
    snprintf(a, sizeof a, "%-16.16s", l1); snprintf(b, sizeof b, "%-16.16s", l2);   // pad: no leftovers
    lcd->setCursor(0, 0); lcd->print(a); lcd->setCursor(0, 1); lcd->print(b);
}

static void supply_text(char* out, size_t n, double v, int energised_here) {
    if (v < 115.0 || !energised_here) { snprintf(out, n, "OFF"); return; }   // below 0.5 pu = no supply
    switch (d_mode) {
        case 1:  snprintf(out, n, "GRID"); break;
        case 2:  snprintf(out, n, "ISLAND"); break;
        case 3:  snprintf(out, n, "ISLAND (SYNC)"); break;
        case 0:  snprintf(out, n, "STARTING"); break;
        default: snprintf(out, n, "ON (mode ?)"); break;
    }
}

static void render(bool estop) {
    if (!lcd) return;
    const int r = d_role ? d_role : (role == 'B' ? 4 : 0);
    const char* nm = NODE_NAME[r];
    char l1[24], l2[24];
    if (role == '?') { show("URJA microgrid", "waiting for MCU"); return; }
    const int npages = (r == 4) ? 7 : (r == 3 ? 4 : 5);
    const int p = page % npages;
    if (r == 4) {                                            // solar + BESS node
        const double vdc = BESS_V_DC_NOM * (0.95 + 0.10 * si.soc);
        switch (p) {
            case 0: snprintf(l1, sizeof l1, "%s Supply", nm); supply_text(l2, sizeof l2, si.v_c, 1); break;
            case 1: snprintf(l1, sizeof l1, "%s Total demand", nm); snprintf(l2, sizeof l2, "%.2f kW", d_total / 1000.0); break;
            case 2: snprintf(l1, sizeof l1, "%s Solar", nm); snprintf(l2, sizeof l2, "%.2f kW", si.p_cpv / 1000.0); break;
            case 3: snprintf(l1, sizeof l1, "%s Battery", nm);
                    snprintf(l2, sizeof l2, "%s", si.bess_status ? "FAULT" : (si.p_bess > 50 ? "DISCHARGING" : (si.p_bess < -50 ? "CHARGING" : "IDLE"))); break;
            case 4: snprintf(l1, sizeof l1, "%s SOC", nm); snprintf(l2, sizeof l2, "%.1f %%", 100.0 * si.soc); break;
            case 5: snprintf(l1, sizeof l1, "%s Battery V", nm); snprintf(l2, sizeof l2, "%.1f V", vdc); break;
            default: snprintf(l1, sizeof l1, "%s Battery I", nm); snprintf(l2, sizeof l2, "%.1f A %s", fabs(si.p_bess) / vdc, si.p_bess >= 0 ? "out" : "in"); break;
        }
    } else if (r == 3) {                                     // community load node
        switch (p) {
            case 0: snprintf(l1, sizeof l1, "%s Supply", nm); supply_text(l2, sizeof l2, li.v, lo.tie); break;
            case 1: snprintf(l1, sizeof l1, "%s Critical load", nm); snprintf(l2, sizeof l2, "%s", lo.tie ? "ON" : "OFF"); break;
            case 2: snprintf(l1, sizeof l1, "%s Pump (flex)", nm); snprintf(l2, sizeof l2, "%s", lo.flex ? "ON" : "OFF"); break;
            default: snprintf(l1, sizeof l1, "%s Protection", nm);
                    snprintf(l2, sizeof l2, "%s", lo.hstate == 0 ? "NORMAL" : (lo.hstate == 1 ? "FAULT: TRIPPED" : (lo.hstate == 2 ? "FAULT: LOCKED" : "E-STOP"))); break;
        }
    } else {                                                 // house H1 / H2
        const double net = li.p_load - li.p_pv;
        switch (p) {
            case 0: snprintf(l1, sizeof l1, "%s Supply", nm); supply_text(l2, sizeof l2, li.v, lo.tie); break;
            case 1: snprintf(l1, sizeof l1, "%s Demand", nm); snprintf(l2, sizeof l2, "%.2f kW", li.p_load / 1000.0); break;
            case 2: snprintf(l1, sizeof l1, "%s Solar", nm); snprintf(l2, sizeof l2, "%.2f kW", li.p_pv / 1000.0); break;
            case 3: snprintf(l1, sizeof l1, "%s Net power", nm);
                    if (fabs(net) < 20) { snprintf(l2, sizeof l2, "BALANCED"); }
                    else { snprintf(l2, sizeof l2, "%s %.2f kW", net > 0 ? "IMPORT" : "EXPORT", fabs(net) / 1000.0); }
                    break;
            default: snprintf(l1, sizeof l1, "%s Flexible load", nm);
                    snprintf(l2, sizeof l2, "%s", lo.flex ? "ON" : (lo.hstate ? "OFF (TRIPPED)" : "OFF")); break;
        }
    }
    const int comm_lost = (role == 'B') ? so.comm_lost : lo.comm_lost;
    const int latched = (role == 'B') ? (so.clamped == 2) : (lo.hstate == 3);
    if (estop) snprintf(l2, sizeof l2, "E-STOP PRESSED");
    else if (latched) snprintf(l2, sizeof l2, "E-STOP: RESET");
    else if (comm_lost && p == 0) snprintf(l2, sizeof l2, "NO MAIN CTRL");
    if (!estop && link_lost()) { snprintf(l1, sizeof l1, "MATLAB LINK LOST"); snprintf(l2, sizeof l2, "check script/USB"); }
    show(l1, l2);
}

static void lcd_start() {
    Wire.begin(LCD_SDA, LCD_SCL);
    const uint8_t addrs[2] = {0x27, 0x3F};
    for (int k = 0; k < 2; k++) {
        Wire.beginTransmission(addrs[k]);
        if (Wire.endTransmission() == 0) { lcd = new LiquidCrystal_I2C(addrs[k], 16, 2); break; }
    }
    if (!lcd) return;                                        // no LCD found: the node still works
    lcd->init(); lcd->backlight();
    show("URJA microgrid", "node starting");
}

void setup() {
    const int pins[4] = {LED_A, LED_B, LED_C, LED_D};
    for (int i = 0; i < 4; i++) { pinMode(pins[i], OUTPUT); digitalWrite(pins[i], LOW); }
    pinMode(ESTOP_PIN, INPUT_PULLUP);
    Serial.setRxBufferSize(1024);
    Serial.begin(SERIAL_BAUD);
    reset_all();
    lcd_start();
    Serial.println("READY");
}

static bool parse_D(const char* s) {                       // D,seq,mode,total_w,role
    long seq; int mode, r; double tot;
    if (sscanf(s, "D,%ld,%d,%lf,%d", &seq, &mode, &tot, &r) != 4) return false;
    d_mode = mode; d_total = tot; d_role = (r >= 1 && r <= 4) ? r : 0;
    return true;
}

void loop() {
    const bool estop = digitalRead(ESTOP_PIN) == LOW || soft_estop;
    leds(estop);
    while (Serial.available()) {
        char ch = (char)Serial.read();
        if (ch == '\r') continue;
        if (ch != '\n') { if (len < sizeof(line) - 1) line[len++] = ch; continue; }
        line[len] = '\0'; len = 0;
        t_rx = millis();
        if (line[0] == 'R') { reset_all(); Serial.println("READY"); continue; }
        if (line[0] == 'S') { soft_estop = (line[1] == ',' && line[2] == '1'); continue; }   // no reply
        if (line[0] == 'D') { parse_D(line); continue; }    // display info: no reply
        if (line[0] == 'L') {
            LoadIn x;
            if (!parse_L(line, x)) { Serial.println("E,parse"); continue; }
            role = 'L'; load_step(ls, x, lo, estop); li = x;
            format_l(reply, sizeof reply, x, lo);
        } else if (line[0] == 'B') {
            SbIn x;
            if (!parse_B(line, x)) { Serial.println("E,parse"); continue; }
            role = 'B'; sb_step(bs, x, so, estop); bess_fault = x.bess_status; sb_p_meas = x.p_bess; si = x;
            format_b(reply, sizeof reply, x, so);
        } else { Serial.println("E,unknown"); continue; }
        Serial.println(reply);                               // reply first, display after
    }
    const unsigned long now = millis();
    if (now - t_page >= PAGE_MS) { t_page = now; page++; }
    if (now - t_ref >= REFRESH_MS && !Serial.available()) { t_ref = now; render(estop); }
}
