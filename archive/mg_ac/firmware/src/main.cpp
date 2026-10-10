// main.cpp - ESP32 firmware for the AC community microgrid (MATLAB plant over USB).
// Each "M" line from MATLAB = one tick: parse -> ctrl_step -> reply "C" line,
// update the 4 indicator LEDs, and every TELEMETRY_EVERY ticks print one
// "T{json}" line in the AI/ML data-contract format (docs/data_contract.md).
// "R" resets the controller and answers READY. Everything OFF at boot.
//   LED_GRID   green : grid breaker closed
//   LED_ISLAND red   : islanded (solid) / synchronising (blinking)
//   LED_SHED   yellow: some flexible load shed (battery, frequency or AI)
//   LED_FAULT  white : house lockout, BESS fault, or E-stop pressed
#ifndef SIL_HOST
#include <Arduino.h>
#include "controller.h"
#include "protocol.h"

static CtrlState st;
static Out out;
static Meas meas;
static char line[640];
static size_t len = 0;
static char reply[256];


static void leds(bool estop) {
    const bool blink = (millis() / 250) % 2;
    digitalWrite(LED_GRID,   (!estop && (out.bits & 1u)) ? HIGH : LOW);
    digitalWrite(LED_ISLAND, (!estop && (out.mode == MODE_ISLAND || (out.mode == MODE_RESYNC && blink))) ? HIGH : LOW);
    digitalWrite(LED_SHED,   (!estop && (out.flags & 16)) ? HIGH : LOW);
    digitalWrite(LED_FAULT,  (estop || (out.flags & (8 | 32))) ? HIGH : LOW);
}

static void kv(const char* k, double v, int d) { Serial.print(",\""); Serial.print(k); Serial.print("\":"); Serial.print(v, d); }

static void print_telemetry(const Meas& m, const Out& o) {
    Serial.print("T{\"t_ms\":"); Serial.print(m.t_ms);
    Serial.print(",\"mode\":"); Serial.print(o.mode);
    kv("price_rs_kwh", o.price, 3);
    Serial.print(",\"grid\":{\"available\":"); Serial.print((o.flags & 1) ? "true" : "false");
    kv("voltage_v", m.v_grid, 2); kv("frequency_hz", m.f_grid, 3);
    kv("p_w", m.p_pcc, 1); kv("q_var", m.q_pcc, 1);
    Serial.print(",\"breaker\":\""); Serial.print((o.bits & 1u) ? "CLOSED" : "OPEN"); Serial.print("\"}");
    Serial.print(",\"bus\":{\"voltage_v\":"); Serial.print(m.v_c, 2); kv("frequency_hz", m.f_mg, 3);
    kv("dtheta_deg", m.dtheta, 2); Serial.print("}");
    Serial.print(",\"bess\":{\"soc\":"); Serial.print(m.soc * 100.0, 2);
    kv("p_w", m.p_bess, 1); kv("q_var", m.q_bess, 1); kv("p_set_w", o.p_set, 1); kv("q_set_var", o.q_set, 1);
    kv("max_charge_w", BESS_P_CH, 0); kv("max_discharge_w", BESS_P_DIS, 0);
    Serial.print(",\"fault\":"); Serial.print(m.bess_status ? "true" : "false"); Serial.print("}");
    Serial.print(",\"community\":{\"load_p_w\":"); Serial.print(m.p_cl, 1); kv("load_q_var", m.q_cl, 1);
    kv("pv_p_w", m.p_cpv, 1); Serial.print("}");
    Serial.print(",\"houses\":[");
    for (int k = 0; k < N_HOUSES; k++) {
        if (k) Serial.print(',');
        Serial.print("{\"house_id\":\""); Serial.print(HOUSE_ID[k]); Serial.print("\"");
        kv("voltage_v", m.v_h[k], 2); kv("current_a", m.i_h[k], 3);
        kv("load_p_w", m.p_load[k], 1); kv("load_q_var", m.q_load[k], 1);
        kv("pv_p_w", m.p_pv[k], 1); kv("pv_q_var", m.q_pv[k], 1);
        kv("net_p_w", m.p_pv[k] - m.p_load[k], 1); kv("balance_rs", o.bal[k], 3);
        Serial.print(",\"critical_on\":"); Serial.print((o.bits >> (2 + 2 * k)) & 1u);
        Serial.print(",\"flexible_on\":"); Serial.print((o.bits >> (3 + 2 * k)) & 1u);
        Serial.print(",\"status_code\":"); Serial.print(o.hcode[k]);
        Serial.print('}');
    }
    Serial.print("],\"ai_status\":"); Serial.print(o.ai_status);
    Serial.println("}");
}

void setup() {
    const int pins[4] = {LED_GRID, LED_ISLAND, LED_SHED, LED_FAULT};
    for (int i = 0; i < 4; i++) { pinMode(pins[i], OUTPUT); digitalWrite(pins[i], LOW); }
    pinMode(ESTOP_PIN, INPUT_PULLUP);
    Serial.setRxBufferSize(1024);     // an M line is ~270 bytes: the default 256 could overflow
    Serial.begin(SERIAL_BAUD);
    ctrl_init(st);
    out.bits = 0; out.mode = MODE_BOOT; out.flags = 0;
    Serial.println("READY");
}

void loop() {
    const bool estop = digitalRead(ESTOP_PIN) == LOW;
    leds(estop);
    while (Serial.available()) {
        char c = (char)Serial.read();
        if (c == '\r') continue;
        if (c != '\n') { if (len < sizeof(line) - 1) line[len++] = c; continue; }
        line[len] = '\0'; len = 0;
        if (line[0] == 'R') { ctrl_init(st); out.bits = 0; out.mode = MODE_BOOT; out.flags = 0; Serial.println("READY"); continue; }
        if (!proto_parse_meas(line, meas)) { Serial.println("E,parse"); continue; }
        ctrl_step(st, meas, out);
        if (estop) { out.bits = 0; out.flags |= 128; }       // E-stop: open everything
        // telemetry first, reply last: MATLAB sends the next line only after the reply,
        // so the ESP32 is never busy printing while a new line arrives
        if (TELEMETRY_EVERY > 0 && st.tick % TELEMETRY_EVERY == 0) print_telemetry(meas, out);
        proto_format_cmd(reply, sizeof(reply), meas.seq, out);
        Serial.println(reply);
    }
}
#endif
