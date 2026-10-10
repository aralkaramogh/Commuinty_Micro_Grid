// restoration.cpp - Load restoration engine
// Port of MATLAB src/load_restoration_engine.m
#include "restoration.h"
#include <math.h>
#include <stdio.h>

// Load parameters (must match config.h / params)
static const float LOAD_R[4]      = {LOAD1_R_OHM, LOAD2_R_OHM, LOAD3_R_OHM, LOAD4_R_OHM};
static const float LOAD_PNOM[4]   = {LOAD1_P_NOM_W, LOAD2_P_NOM_W, LOAD3_P_NOM_W, LOAD4_P_NOM_W};
static const float LOAD_INRUSH[4] = {LOAD1_INRUSH, LOAD2_INRUSH, LOAD3_INRUSH, LOAD4_INRUSH};
static const float LOAD_SOC[4]    = {LOAD1_SOC_MIN, LOAD2_SOC_MIN, LOAD3_SOC_MIN, LOAD4_SOC_MIN};
static const float MIN_OFF_S = 5.0f;  // minimum off-time before re-connect

void rest_step(FsmState_t_struct*s, const Sensors_t*sens, float t_s) {
    float Vb = sens->V_bus;
    float Is = sens->I_src;

    // Headroom judged against SHORT-TERM source rating (inrush lasts <=0.15 s);
    // steady-state still gated by Is < STOR_I_LIM*REST_ISRC_FRAC below.
    float P_src_inrush = fmaxf(0.0f, (STOR_I_INRUSH_MAX - Is)*Vb);
    float P_pv_avail   = s->pv_sw ? fmaxf(0.0f, (sens->V_pv - Vb)*0.1f) : 0.0f; // crude, same as MATLAB
    float P_avail      = P_src_inrush + P_pv_avail;

    // ---- Per-tier strike clearing: healthy for REST_T_STRIKE_CLEAR_S ----
    for(int i=0;i<4;i++)
        if(s->load_state[i] && (t_s - s->t_conn_s[i]) >= REST_T_STRIKE_CLEAR_S - TMR_EPS) s->tier_strikes[i]=0;

    // ---- SHEDDING (emergency) --------------------------------------
    bool stressed = (Vb < V_NOM_V*0.90f) || (Is > I_OC_SOFT_A) || (s->SOC < SOC_CRIT);
    bool blamed = false;
    int  lc = s->last_conn_idx;
    if(stressed && lc>=0 && s->load_state[lc] && (t_s - s->t_last_step_s) <= REST_T_BLAME_S + TMR_EPS){
        // Stress right after a connect: blame and shed that load
        s->load_state[lc]=false; s->t_last_shed_s[lc]=t_s; s->load_mask &= ~(1<<lc);
        s->n_shed_events++; s->tier_strikes[lc]++; s->last_conn_idx=-1; s->t_blame_s=t_s; blamed=true;
        printf("[REST %.2f] BLAME+SHED load%d (strike %d)\n", t_s, lc+1, s->tier_strikes[lc]);
        if(s->tier_strikes[lc] >= REST_MAX_STRIKES){
            s->tier_locked[lc]=true;
            printf("[REST %.2f] TIER LOCKOUT load%d: faulty branch isolated\n", t_s, lc+1);
        }
    }
    bool in_holdoff = (t_s - s->t_blame_s) < REST_T_SHED_HOLDOFF_S - TMR_EPS;
    if(stressed && !blamed && !in_holdoff){
        for(int i=3;i>=1;i--){  // T4 down to T2 (never shed T1 top-down)
            if(s->load_state[i]){
                s->load_state[i]=false;
                s->t_last_shed_s[i]=t_s;
                s->load_mask &= ~(1<<i);
                s->n_shed_events++;
                printf("[REST %.2f] SHED load%d: Vb=%.2f Is=%.2f SOC=%.2f\n", t_s,i+1,Vb,Is,s->SOC);
                break;
            }
        }
    }

    // ---- RESTORATION (opportunistic) -------------------------------
    bool settle_ok = (t_s - s->t_last_step_s) >= T_LOAD_STEP_SETTLE_S - TMR_EPS;
    bool bus_ok    = fabsf(Vb - V_NOM_V)/V_NOM_V < V_STABLE_BAND;

    if(settle_ok && bus_ok && !stressed){
        for(int i=0;i<4;i++){
            if(s->load_state[i]) continue;          // already on
            if(s->tier_locked[i]) continue;         // faulty branch locked out
            if((t_s - s->t_last_shed_s[i]) < MIN_OFF_S) continue;
            if(s->SOC < LOAD_SOC[i]) continue;
            float P_step = LOAD_PNOM[i] * LOAD_INRUSH[i] * REST_K_COLD * REST_MARGIN;
            if(P_avail >= P_step && Is < STOR_I_LIM*REST_ISRC_FRAC){
                s->load_state[i]=true;
                s->load_connect_time_s[i]=t_s;
                s->load_mask |= (1<<i);
                s->t_last_step_s=t_s;
                s->last_conn_idx=(int8_t)i;
                s->t_conn_s[i]=t_s;
                printf("[REST %.2f] CONNECT load%d: P_step=%.2f avail=%.2f SOC=%.2f\n",
                    t_s,i+1,P_step,P_avail,s->SOC);
                break;  // one at a time
            }
        }
    }

    // Check if all restorable (non-locked) loads are on
    s->restoration_complete=true;
    for(int i=0;i<4;i++){
        if(s->SOC >= LOAD_SOC[i] && !s->load_state[i] && !s->tier_locked[i]){
            s->restoration_complete=false; break;
        }
    }
}
