// protection.cpp - Hardware protection checks
// Mirrors MATLAB check_protection() in blackstart_fsm.m (keep in sync!)
#include "protection.h"
#include <math.h>
#include <stdio.h>

void prot_check(FsmState_t_struct*s, const Sensors_t*sens, float t_s) {
    (void)t_s;
    const float dt = TS_FSM_MS/1000.0f;
    const float Vb=sens->V_bus, Is=sens->I_src;
    const bool  in_fault_or_lock = (s->state==SX_FAULT_RECOVERY || s->state==SX_LOCKOUT_ALARM);

    if(!s->src_connected){
        s->I2t_accum = fmaxf(0.0f, s->I2t_accum - I2T_LIMIT*0.01f*dt);
        return;
    }

    // Leaky I2t: only current above the continuous rating (I_oc_soft) heats the path
    s->I2t_accum = fmaxf(0.0f, s->I2t_accum + (Is*Is - I_OC_SOFT_A*I_OC_SOFT_A)*dt);

    // Hard over-current, must persist for T_OC_TRIP_S (rejects noise spikes)
    if(Is > I_OC_HARD_A){
        s->t_oc_confirm += dt;
        if(s->t_oc_confirm >= T_OC_TRIP_S && !in_fault_or_lock){
            s->fault_latched=true; s->fault_code=FAULT_OC_HARD;
            printf("[PROT] OC_HARD: Is=%.3fA\n",Is);
        }
    } else s->t_oc_confirm = 0.0f;

    // Source-switch health: duty~1 and Vb below V_oc => source must conduct
    float I_expect = (STOR_V_OC - Vb)/STOR_R_SER;
    if(s->state>=S6_LOAD_RESTORATION && s->state<=S7_NORMAL_ISLANDED &&
       s->src_duty>=0.95f-TMR_EPS && I_expect>I_SW_EXPECT_MIN_A && Is<0.05f){
        s->t_sw_mismatch += dt;
        if(s->t_sw_mismatch >= T_SW_MISMATCH_S){
            s->fault_latched=true; s->fault_code=FAULT_SWITCH;
            printf("[PROT] SWITCH_FAULT\n");
        }
    } else s->t_sw_mismatch = 0.0f;

    // Frozen Vbus sensor
    if(fabsf(Vb - s->Vb_last) < 1e-6f){
        s->t_Vb_still += dt;
        if(s->t_Vb_still >= SENSOR_FREEZE_S){
            s->fault_latched=true; s->fault_code=FAULT_SENSOR_FROZEN;
            printf("[PROT] SENSOR_FROZEN\n");
        }
    } else s->t_Vb_still = 0.0f;
    s->Vb_last = Vb;

    // I2t trip
    if(s->I2t_accum > I2T_LIMIT && !in_fault_or_lock){
        s->fault_latched=true; s->fault_code=FAULT_I2T;
        printf("[PROT] I2T: %.3f\n",s->I2t_accum);
    }

    // Over-voltage
    if(Vb > V_OV_TRIP && !in_fault_or_lock){
        s->fault_latched=true; s->fault_code=FAULT_OV;
        printf("[PROT] OV: Vb=%.3fV\n",Vb);
    }
}
