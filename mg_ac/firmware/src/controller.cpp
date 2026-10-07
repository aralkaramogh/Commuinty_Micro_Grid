// controller.cpp - see controller.h. Keep equivalent to ac_controller_step.m.
#include "controller.h"
#include <math.h>

static double wrap180(double a) { return a - 360.0 * floor((a + 180.0) / 360.0); }

void ctrl_init(CtrlState& st) {
    st.tick = 0; st.mode = MODE_BOOT; st.n_good = 0; st.n_bad = 0; st.last_bits = 0;
    st.n_island = 0; st.n_reconnect = 0; st.uf_hold = 0;
    for (int k = 0; k < N_HOUSES; k++) {
        st.hstate[k] = 0; st.n_oc[k] = 0; st.strikes[k] = 0; st.n_healthy[k] = 0; st.retry[k] = 0;
        st.shed_soc[k] = 0; st.shed_uf[k] = 0; st.shed_ai[k] = 0;
        st.bal[k] = HOUSE_CREDIT0[k]; st.credit_ok[k] = st.bal[k] > 0 ? 1 : 0;
        st.bad[k] = 0; st.card_lock[k] = 0;
    }
    st.price = PRICE_DEFAULT; st.ai_active = 0; st.ai_age = 0; st.ai_p = 0;
}

void ctrl_step(CtrlState& st, const Meas& m, Out& o) {
    const double dt = DT_S, V0 = V_NOM;
    st.tick = st.tick + 1;

    // ---------- grid health ----------
    const double vg = m.v_grid / V0;
    const bool grid_ok = vg >= V_OK_LO && vg <= V_OK_HI && m.f_grid >= F_OK_LO && m.f_grid <= F_OK_HI;
    const bool grid_lost = vg < V_LOST;
    if (grid_ok) { st.n_good = st.n_good + 1; st.n_bad = 0; }
    else         { st.n_bad = st.n_bad + 1;   st.n_good = 0; }
    const bool mismatch = (st.tick > 1) && (m.fb != st.last_bits);
    const double soc = m.soc;
    const bool bess_fault = m.bess_status != 0;

    // ---------- operating mode ----------
    switch (st.mode) {
    case MODE_BOOT:
        if (st.tick > N_BOOT) st.mode = MODE_ISLAND;
        break;
    case MODE_GRID:
        if (grid_lost || st.n_bad >= N_ABN) { st.mode = MODE_ISLAND; st.n_island = st.n_island + 1; }
        break;
    case MODE_ISLAND:
        if (st.n_good >= N_GRID_STABLE) st.mode = MODE_RESYNC;
        break;
    case MODE_RESYNC:
        if (!grid_ok) {
            st.mode = MODE_ISLAND;
        } else if (m.v_c < V_LOST * V0) {
            st.mode = MODE_GRID; st.n_reconnect = st.n_reconnect + 1;      // dead-bus closing
        } else {
            const double pred = wrap180(m.dtheta + 360.0 * (m.f_mg - m.f_grid) * dt);
            if (fabs(m.v_grid - m.v_c) <= DV_SYNC && fabs(m.f_mg - m.f_grid) <= DF_SYNC && fabs(pred) <= DTH_SYNC) {
                st.mode = MODE_GRID; st.n_reconnect = st.n_reconnect + 1;
            }
        }
        break;
    }
    const bool booted = st.mode != MODE_BOOT;
    const bool island = st.mode == MODE_ISLAND || st.mode == MODE_RESYNC;
    const bool gridm  = st.mode == MODE_GRID;

    // ---------- AI advisor command ----------
    int ai_status = 0;
    if (m.ai_valid != 0) {
        st.ai_active = 1; st.ai_age = 0; st.ai_p = m.ai_p;
        for (int k = 0; k < N_HOUSES; k++) st.shed_ai[k] = (m.ai_mask & (1u << k)) ? 1 : 0;
        if (m.ai_price >= PRICE_MIN && m.ai_price <= PRICE_MAX) st.price = m.ai_price;
        else ai_status = ai_status + 4;
    } else if (st.ai_active) {
        st.ai_age = st.ai_age + dt;
        if (st.ai_age > T_AI_TIMEOUT) {
            st.ai_active = 0; for (int k = 0; k < N_HOUSES; k++) st.shed_ai[k] = 0; st.price = PRICE_DEFAULT;
        }
    }
    if (st.ai_active) ai_status = ai_status + 1;

    // ---------- RFID cards ----------
    for (int k = 0; k < N_HOUSES; k++) if (st.card_lock[k] > 0) st.card_lock[k] = st.card_lock[k] - 1;
    if (m.card_uid != 0 && m.card_house >= 1 && m.card_house <= N_HOUSES) {
        const int k = m.card_house - 1;
        if (st.card_lock[k] > 0) {
            // locked: ignore
        } else if (m.card_uid == HOUSE_CARD_UID[k]) {
            st.bal[k] = st.bal[k] + CARD_TOPUP; st.bad[k] = 0;
        } else {
            st.bad[k] = st.bad[k] + 1;
            if (st.bad[k] >= CARD_BAD_MAX) { st.card_lock[k] = N_CARD_LOCK; st.bad[k] = 0; }
        }
    }

    // ---------- island under-frequency load shedding ----------
    if (island) {
        if (m.f_mg > 0 && m.f_mg < F_UFLS) {
            for (int k = N_HOUSES - 1; k >= 0; k--) { if (st.shed_uf[k] == 0) { st.shed_uf[k] = 1; break; } }
            st.uf_hold = T_UF_HOLD;
        } else if (st.uf_hold > 0) {
            st.uf_hold = st.uf_hold - dt;
        } else {
            for (int k = 0; k < N_HOUSES; k++) {
                if (st.shed_uf[k] == 1) {
                    if (m.p_bess + HOUSE_P_FLEX[k] <= UF_RESTORE * BESS_P_DIS) { st.shed_uf[k] = 0; st.uf_hold = T_UF_STEP; }
                    break;
                }
            }
        }
    } else {
        for (int k = 0; k < N_HOUSES; k++) st.shed_uf[k] = 0;
        st.uf_hold = 0;
    }

    // ---------- per house ----------
    uint32_t bits = 0; int any_locked = 0, any_shed = 0, any_card = 0;
    for (int k = 0; k < N_HOUSES; k++) {
        const bool tie_fb = (m.fb & (1u << (2 + 2 * k))) != 0;
        if (st.hstate[k] == 0) {
            if (tie_fb && m.i_h[k] > I_TRIP) st.n_oc[k] = st.n_oc[k] + 1; else st.n_oc[k] = 0;
            if (st.n_oc[k] >= N_OC) {
                st.strikes[k] = st.strikes[k] + 1; st.n_oc[k] = 0; st.n_healthy[k] = 0;
                if (st.strikes[k] >= STRIKES_MAX) st.hstate[k] = 2;
                else { st.hstate[k] = 1; st.retry[k] = N_RETRY; }
            } else {
                st.n_healthy[k] = st.n_healthy[k] + 1;
                if (st.n_healthy[k] >= N_STRIKE_CLEAR) st.strikes[k] = 0;
            }
        } else if (st.hstate[k] == 1) {
            st.retry[k] = st.retry[k] - 1;
            if (st.retry[k] <= 0) { st.hstate[k] = 0; st.n_healthy[k] = 0; }
        }
        if (island) {
            if (soc < HOUSE_SHED_SOC[k]) st.shed_soc[k] = 1;
            else if (soc > HOUSE_SHED_SOC[k] + SOC_HYST) st.shed_soc[k] = 0;
        } else {
            st.shed_soc[k] = 0;
        }
        const double p_net = m.p_load[k] - m.p_pv[k];
        if (p_net > 0) st.bal[k] = st.bal[k] - p_net * dt / 3600 / 1000 * st.price;
        else           st.bal[k] = st.bal[k] - p_net * dt / 3600 / 1000 * st.price * SELL_RATIO;
        if (st.bal[k] <= 0) st.credit_ok[k] = 0;
        else if (st.bal[k] >= CREDIT_RESTORE) st.credit_ok[k] = 1;
        const int tie  = (booted && st.hstate[k] == 0) ? 1 : 0;
        const int flex = (tie && st.shed_soc[k] == 0 && st.shed_uf[k] == 0 && st.shed_ai[k] == 0 && st.credit_ok[k] == 1) ? 1 : 0;
        bits += (uint32_t)tie << (2 + 2 * k);
        bits += (uint32_t)flex << (3 + 2 * k);
        if (st.hstate[k] == 2) any_locked = 1;
        if (st.shed_soc[k] || st.shed_uf[k] || st.shed_ai[k]) any_shed = 1;
        if (st.card_lock[k] > 0) any_card = 1;
        o.bal[k] = st.bal[k];
        o.hcode[k] = st.hstate[k] + 4 * st.shed_soc[k] + 8 * (1 - st.credit_ok[k]) + 16 * (st.card_lock[k] > 0 ? 1 : 0)
                   + 32 * st.shed_uf[k] + 64 * st.shed_ai[k];
    }

    // ---------- BESS set-points (used only while grid-connected) ----------
    double p_set = 0, q_set = 0;
    if (gridm) {
        double net_p = m.p_cl - m.p_cpv, net_q = m.q_cl;
        for (int k = 0; k < N_HOUSES; k++) {
            net_p = net_p + m.p_load[k] - m.p_pv[k];
            net_q = net_q + m.q_load[k] - m.q_pv[k];
        }
        double p_lo = 0; if (soc < SOC_CH_STOP) p_lo = -BESS_P_CH;
        if (st.ai_active) {
            double p_hi = 0; if (soc > SOC_AI_MIN) p_hi = BESS_P_DIS;
            p_set = fmin(fmax(st.ai_p, p_lo), p_hi);
            if (p_set != st.ai_p) ai_status = ai_status + 2;
        } else {
            double p_hi = 0; if (soc > SOC_RESERVE) p_hi = BESS_P_DIS;
            p_set = fmin(fmax(net_p, p_lo), p_hi);
            if (soc < SOC_RESERVE) p_set = fmax(fmin(p_set, -P_RECHARGE), p_lo);   // rebuild the outage reserve
        }
        const double q_av = sqrt(fmax(0.0, BESS_S * BESS_S - p_set * p_set));
        q_set = fmin(fmax(net_q, -q_av), q_av);
    } else if (st.ai_active && st.ai_p != 0) {
        ai_status = ai_status + 8;
    }

    bits += (gridm ? 1u : 0u) + (st.mode == MODE_RESYNC ? 2u : 0u);
    st.last_bits = bits;
    o.bits = bits; o.mode = st.mode; o.p_set = p_set; o.q_set = q_set;
    o.ai_status = ai_status; o.price = st.price;
    o.flags = (grid_ok ? 1 : 0) + 2 * (mismatch ? 1 : 0) + 4 * any_card + 8 * any_locked + 16 * any_shed
            + 32 * (bess_fault ? 1 : 0) + 64 * st.ai_active;
}
