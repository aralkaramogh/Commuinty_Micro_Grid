// node.cpp - node controller rules + text lines. Must stay identical to
// nodes/node_load_step.m, nodes/node_sb_step.m and comms/node_lines.m.
#include "node.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

void load_init(LoadSt& s) {
    s.enabled = 0; s.flex_allow = 0; s.n_nocmd = 0;
    s.hstate = 0; s.n_oc = 0; s.strikes = 0; s.n_healthy = 0; s.retry = 0;
    s.tie = 0; s.flex = 0; s.e_imp = 0; s.e_exp = 0; s.estop = 0;
}

void load_step(LoadSt& s, const LoadIn& x, LoadOut& r, bool estop) {
    if (estop) s.estop = 1;                      // E-stop latch (cleared only by load_init)
    if (x.valid) {
        s.n_nocmd = 0;
        if (x.enable) s.enabled = 1;             // latched: a command never switches critical off
        s.flex_allow = x.flex_allow;
    } else {
        s.n_nocmd = (s.n_nocmd + 1 < 1000000L) ? s.n_nocmd + 1 : 1000000L;
    }
    const bool comm_lost = s.n_nocmd >= N_COMM_LOST;
    if (s.estop) {
        // E-stop latched: protection frozen, relays forced open below
    } else if (s.hstate == 0) {                  // over-current protection
        if (s.tie && x.i > I_TRIP) s.n_oc++; else s.n_oc = 0;
        if (s.n_oc >= N_OC) {
            s.strikes++; s.n_oc = 0; s.n_healthy = 0;
            if (s.strikes >= STRIKES_MAX) s.hstate = 2;
            else { s.hstate = 1; s.retry = N_RETRY; }
        } else {
            s.n_healthy++;
            if (s.n_healthy >= N_STRIKE_CLEAR) s.strikes = 0;
        }
    } else if (s.hstate == 1) {
        s.retry--;
        if (s.retry <= 0) { s.hstate = 0; s.n_healthy = 0; }
    }
    s.tie  = (s.enabled == 1 && s.hstate == 0 && s.estop == 0) ? 1 : 0;
    s.flex = (s.tie == 1 && s.flex_allow == 1 && !comm_lost) ? 1 : 0;
    const double p_net = x.p_load - x.p_pv;      // energy counters [Wh]
    if (p_net > 0) s.e_imp = s.e_imp + p_net * DT_S / 3600;
    else           s.e_exp = s.e_exp - p_net * DT_S / 3600;
    r.tie = s.tie; r.flex = s.flex; r.hstate = s.estop ? 3 : s.hstate; r.strikes = s.strikes;
    r.comm_lost = comm_lost ? 1 : 0; r.e_imp = s.e_imp; r.e_exp = s.e_exp;
}

void sb_init(SbSt& s) { s.n_nocmd = 0; s.p_cmd = 0; s.q_cmd = 0; s.sync_cmd = 0; s.estop = 0; }

static double mn(double a, double b) { return a < b ? a : b; }
static double mx(double a, double b) { return a > b ? a : b; }

void sb_step(SbSt& s, const SbIn& x, SbOut& r, bool estop) {
    if (estop) s.estop = 1;                      // E-stop latch
    if (x.valid) { s.n_nocmd = 0; s.p_cmd = x.p_set; s.q_cmd = x.q_set; s.sync_cmd = x.sync; }
    else s.n_nocmd = (s.n_nocmd + 1 < 1000000L) ? s.n_nocmd + 1 : 1000000L;
    const bool comm_lost = s.n_nocmd >= N_COMM_LOST;
    const double p_hi = (x.soc > SOC_FLOOR)   ? BESS_P_DIS : 0.0;
    const double p_lo = (x.soc < SOC_CH_STOP) ? -BESS_P_CH : 0.0;
    const double p = mn(mx(s.p_cmd, p_lo), p_hi);
    const double q_av = sqrt(mx(0.0, BESS_S * BESS_S - p * p));
    const double q = mn(mx(s.q_cmd, -q_av), q_av);
    r.p = p; r.q = q;
    r.sync = (s.sync_cmd == 1 && !comm_lost) ? 1 : 0;
    r.clamped = (p != s.p_cmd || q != s.q_cmd) ? 1 : 0;
    r.comm_lost = comm_lost ? 1 : 0;
    if (s.estop) { r.p = 0; r.q = 0; r.sync = 0; r.clamped = 2; }   // inverter stopped
}

// ---------- text lines ----------
static bool next_d(const char*& p, double& v) {
    if (*p != ',') return false;
    char* e; v = strtod(p + 1, &e);
    if (e == p + 1) return false;
    p = e; return true;
}
static bool at_end(const char* p) { return *p == '\0' || *p == '\r' || *p == '\n'; }

bool parse_L(const char* line, LoadIn& x) {
    if (line[0] != 'L') return false;
    const char* p = line + 1; double v[11];
    for (int k = 0; k < 11; k++) if (!next_d(p, v[k])) return false;
    x.seq = (long)v[0]; x.valid = (int)v[1]; x.enable = (int)v[2]; x.flex_allow = (int)v[3];
    x.v = v[4]; x.i = v[5]; x.p_load = v[6]; x.q_load = v[7]; x.p_pv = v[8]; x.q_pv = v[9];
    x.card_uid = (uint32_t)v[10];
    return at_end(p);
}

bool parse_B(const char* line, SbIn& x) {
    if (line[0] != 'B') return false;
    const char* p = line + 1; double v[12];
    for (int k = 0; k < 12; k++) if (!next_d(p, v[k])) return false;
    x.seq = (long)v[0]; x.valid = (int)v[1]; x.p_set = v[2]; x.q_set = v[3]; x.sync = (int)v[4];
    x.soc = v[5]; x.p_bess = v[6]; x.q_bess = v[7]; x.bess_status = (int)v[8];
    x.v_c = v[9]; x.f_mg = v[10]; x.p_cpv = v[11];
    return at_end(p);
}

int format_l(char* buf, size_t len, const LoadIn& x, const LoadOut& r) {
    return snprintf(buf, len, "l,%ld,%d,%d,%d,%d,%d,%.4f,%.4f,%.3f,%.4f,%.2f,%.2f,%.2f,%.2f,%lu",
                    x.seq, r.tie, r.flex, r.hstate, r.strikes, r.comm_lost, r.e_imp, r.e_exp,
                    x.v, x.i, x.p_load, x.q_load, x.p_pv, x.q_pv, (unsigned long)x.card_uid);
}

int format_b(char* buf, size_t len, const SbIn& x, const SbOut& r) {
    return snprintf(buf, len, "b,%ld,%.1f,%.1f,%d,%d,%d,%.6f,%.2f,%.2f,%d,%.3f,%.4f,%.2f",
                    x.seq, r.p, r.q, r.sync, r.clamped, r.comm_lost, x.soc, x.p_bess, x.q_bess,
                    x.bess_status, x.v_c, x.f_mg, x.p_cpv);
}
