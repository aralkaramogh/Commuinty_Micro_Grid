// controller.h - AC community microgrid controller core (no Arduino calls).
// Line-for-line twin of controller/ac_controller_step.m; tools/run_sil.sh
// replays MATLAB frames through this code and requires identical replies.
#pragma once
#include <stdint.h>
#include "config.h"

enum Mode { MODE_BOOT = 0, MODE_GRID = 1, MODE_ISLAND = 2, MODE_RESYNC = 3 };

struct Meas {                    // one "M" line
    long seq, t_ms;
    double v_grid, f_grid, v_c, f_mg, dtheta;
    double p_pcc, q_pcc, p_bess, q_bess, soc;
    int bess_status;
    double p_cl, q_cl, p_cpv;
    uint32_t fb;
    int card_house; uint32_t card_uid;
    int ai_valid; double ai_p; uint32_t ai_mask; double ai_price;
    double v_h[N_HOUSES], i_h[N_HOUSES], p_load[N_HOUSES], q_load[N_HOUSES], p_pv[N_HOUSES], q_pv[N_HOUSES];
};

struct Out {                     // one "C" line
    uint32_t bits; int mode; double p_set, q_set; int flags, ai_status; double price;
    double bal[N_HOUSES]; int hcode[N_HOUSES];
};

struct CtrlState {
    long tick; int mode; long n_good, n_bad; uint32_t last_bits; long n_island, n_reconnect;
    int hstate[N_HOUSES], n_oc[N_HOUSES], strikes[N_HOUSES], retry[N_HOUSES];
    long n_healthy[N_HOUSES];
    int shed_soc[N_HOUSES], shed_uf[N_HOUSES], shed_ai[N_HOUSES];
    double uf_hold;
    double bal[N_HOUSES]; int credit_ok[N_HOUSES]; int bad[N_HOUSES]; int card_lock[N_HOUSES];
    double price; int ai_active; double ai_age, ai_p;
};

void ctrl_init(CtrlState& st);
void ctrl_step(CtrlState& st, const Meas& m, Out& o);
