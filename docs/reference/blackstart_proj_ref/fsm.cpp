// fsm.cpp  -  Black-Start FSM (ESP32, Arduino framework)
// Line-by-line port of MATLAB src/blackstart_fsm.m
// Each case maps directly to a state row in the design spec.
#include "fsm.h"
#include "sensors.h"
#include "protection.h"
#include "restoration.h"
#include <string.h>
#include <math.h>
#include <stdio.h>

#ifdef SIL_TEST_MODE
bool g_sil_auto_auth = true;   // set per-row by the SIL replay (MATLAB p.sim.auto_auth)
#endif

/* ---------- internal helpers -------------------------------------- */
static void do_trans(FsmState_t_struct*s,FsmState_t ns,float t,const char*r);
static void upd_soc (FsmState_t_struct*s,float Is,float Vb,float dt);
static bool sens_ok (const Sensors_t*s);

/* ================================================================= */
void fsm_init(FsmState_t_struct*s){
    memset(s,0,sizeof(*s));
    s->state            = S0_BLACKOUT_DETECT;
    s->SOC              = SOC_INIT;
    s->t_last_step_s    = -1e9f;
    s->t_mppt_last_s    = -1e9f;
    s->Vb_last          = -1.0f;
    s->last_conn_idx    = -1;
    s->t_blame_s        = -1e9f;
    for(int i=0;i<4;i++) s->t_conn_s[i] = -1e9f;
    for(int i=0;i<4;i++) s->t_last_shed_s[i]=-1e9f;
    /* CRITICAL: all gates OFF at boot - fail-safe default */
    s->src_duty=0.0f; s->pv_sw=false; s->load_mask=0;
}

/* ================================================================= */
void fsm_tick(float t,const Sensors_t*sns,FsmState_t_struct*s,Gates_t*g){
    const float dt=TS_FSM_MS/1000.0f;
    const Sensors_t raw = *sns;           // uncorrected readings (used for S2 offset capture)
    Sensors_t corr = *sns;
#ifdef SIL_TEST_MODE
    // Hardware path: sensors.cpp already subtracts the boot-time ACS712 offset.
    // SIL replays uncorrected values, so apply the S2-captured offset here (mirrors MATLAB).
    corr.I_src  -= s->I_src_offset;
    corr.I_load -= s->I_load_offset;
#endif
    sns = &corr;
    float Vb=sns->V_bus, Vpv=sns->V_pv, Is=sns->I_src, Il=sns->I_load;

    if(s->src_connected) upd_soc(s,Is,Vb,dt);
    prot_check(s,sns,t);
    if(s->fault_latched && s->state!=SX_FAULT_RECOVERY && s->state!=SX_LOCKOUT_ALARM){
        if(s->fault_code==FAULT_SWITCH || s->fault_code==FAULT_SENSOR_FROZEN)
            do_trans(s,SX_LOCKOUT_ALARM,t,"PROT_LOCKOUT");   // not recoverable by retry
        else
            do_trans(s,SX_FAULT_RECOVERY,t,"PROT_TRIP");
    }

    switch(s->state){
    default: break;   // STATE_MAX: not a real state

    case S0_BLACKOUT_DETECT:
        s->src_duty=0;s->pv_sw=false;s->load_mask=0;s->src_connected=false;
        s->t_blackout_timer += (Vb < V_BLACKOUT_THRESH*V_NOM_V) ? dt : -s->t_blackout_timer;
        if(s->t_blackout_timer>=T_BLACKOUT_CONFIRM_S-TMR_EPS){
            do_trans(s,S1_AUTH_WAIT,t,"BLACKOUT_CONFIRMED"); s->t_blackout_timer=0;}
        break;

    case S1_AUTH_WAIT:
        s->src_duty=0;s->pv_sw=false;s->load_mask=0;
        if(s->lockout_remaining_s>0){ s->lockout_remaining_s-=dt; }
        else if(s->rfid_event==RFID_INVALID){
            s->rfid_event=RFID_NONE; s->bad_scan_count++;
            if(s->bad_scan_count>=AUTH_LOCKOUT_SCANS){
                s->lockout_remaining_s=AUTH_LOCKOUT_TIME_S;
                do_trans(s,SX_LOCKOUT_ALARM,t,"BAD_SCAN");}}
        else if(s->rfid_event==RFID_VALID){
            s->rfid_event=RFID_NONE; s->bad_scan_count=0;
            do_trans(s,S2_SELF_CHECK,t,"AUTHORISED");}
        #ifdef SIL_TEST_MODE
        else if(g_sil_auto_auth) do_trans(s,S2_SELF_CHECK,t,"AUTO_AUTH");  // mirrors p.sim.auto_auth
        #endif
        break;

    case S2_SELF_CHECK:
        s->src_duty=0;s->pv_sw=false;s->load_mask=0;
        if(!sens_ok(&raw)){s->fault_code=FAULT_SENSOR;do_trans(s,SX_LOCKOUT_ALARM,t,"SENSOR_FAULT");}
        else if(s->SOC<SOC_START_MIN){s->fault_code=FAULT_SOC_LOW;do_trans(s,SX_LOCKOUT_ALARM,t,"SOC_LOW");}
        else{ s->I_src_offset=raw.I_src; s->I_load_offset=raw.I_load;
              do_trans(s,S3_SOFT_START_BUS,t,"SELF_CHECK_PASS");
              s->t_softstart_timer=0; s->t_stable_timer=0; }
        break;

    case S3_SOFT_START_BUS:
        s->pv_sw=false; s->load_mask=0; s->src_connected=true;
        s->src_duty += SS_DDUTY*(TS_FSM_MS/TS_FAST_MS);
        if(s->src_duty>1.0f) s->src_duty=1.0f;
        if(Is>SS_I_LIMIT_A){ s->src_duty-=SS_DDUTY*2.0f; if(s->src_duty<0) s->src_duty=0; }
        s->t_softstart_timer+=dt;
        { bool ib=fabsf(Vb-V_NOM_V)/V_NOM_V<V_STABLE_BAND;
          s->t_stable_timer = (ib && s->src_duty>=0.95f-TMR_EPS) ? s->t_stable_timer+dt : 0.0f; }
        if(s->t_stable_timer>=T_STABLE_MIN_S-TMR_EPS){ do_trans(s,S4_BUS_STABLE_DWELL,t,"BUS_STABLE"); s->t_dwell_timer=0; }
        if(s->t_softstart_timer>3.0f*SS_T_RAMP_S){ s->fault_code=FAULT_SOFTSTART_TIMEOUT; do_trans(s,SX_FAULT_RECOVERY,t,"SS_TIMEOUT"); }
        break;

    case S4_BUS_STABLE_DWELL:
        s->src_duty=1.0f; s->pv_sw=false; s->load_mask=0;
        s->t_dwell_timer+=dt;
        if(s->t_dwell_timer>=T_STABLE_DWELL_S-TMR_EPS) do_trans(s,S5_CONNECT_PV,t,"DWELL_DONE");
        break;

    case S5_CONNECT_PV:
        s->src_duty=1.0f; s->load_mask=0;
        { bool pok=(Vpv>=Vb+PV_V_DIODE+PV_CONN_MARGIN)&&(Vpv>0.5f); s->pv_sw=pok;
          if(pok&&(t-s->t_mppt_last_s>=MPPT_PERIOD_S)){
              float Pp=Vpv*fmaxf(0,Il-Is);
              s->mppt_I_ref+=(Pp>s->P_pv_prev)?MPPT_DI_STEP:-MPPT_DI_STEP;
              if(s->mppt_I_ref<0)s->mppt_I_ref=0;
              s->P_pv_prev=Pp; s->t_mppt_last_s=t;}
          do_trans(s,S6_LOAD_RESTORATION,t,"PV_DONE"); }
        break;

    case S6_LOAD_RESTORATION:
        s->src_duty=1.0f; rest_step(s,sns,t);
        if(s->restoration_complete) do_trans(s,S7_NORMAL_ISLANDED,t,"ALL_RESTORED");
        break;

    case S7_NORMAL_ISLANDED:
        s->src_duty=1.0f; rest_step(s,sns,t);
        if(s->pv_sw && Vb>V_NOM_V*1.05f) s->mppt_I_ref=fmaxf(0,s->mppt_I_ref-MPPT_DI_STEP*3.0f);
        break;

    case SX_FAULT_RECOVERY:
        s->src_duty=0;s->pv_sw=false;s->load_mask=0;s->src_connected=false;
        s->t_fault_timer+=dt;
        { int e=s->retry_count<4?s->retry_count:4;
          float bo=RETRY_BACKOFF_BASE_S*(float)(1<<e);
          if(s->t_fault_timer>=bo){
              if(s->retry_count>=RETRY_MAX){ do_trans(s,SX_LOCKOUT_ALARM,t,"MAX_RETRIES"); }
              else{ s->retry_count++; s->n_retries++; s->t_fault_timer=0; s->fault_latched=false; do_trans(s,S2_SELF_CHECK,t,"RETRY"); }}}
        break;

    case SX_LOCKOUT_ALARM:
        s->src_duty=0;s->pv_sw=false;s->load_mask=0;s->src_connected=false;
        if(s->rfid_event==RFID_VALID){
            s->rfid_event=RFID_NONE; s->retry_count=0; s->fault_latched=false;
            s->fault_code=FAULT_NONE; s->bad_scan_count=0; s->lockout_remaining_s=0;
            do_trans(s,S0_BLACKOUT_DETECT,t,"RFID_RESET");}
        break;
    }
    g->src_duty=s->src_duty; g->pv_sw=s->pv_sw; g->load_mask=s->load_mask;
}

void fsm_inject_rfid(FsmState_t_struct*s,RfidEvent_t ev){ s->rfid_event=ev; }

static void do_trans(FsmState_t_struct*s,FsmState_t ns,float t,const char*r){
    uint8_t i=s->log_head%EVENT_LOG_SIZE;
    s->event_log[i].time_s=t; s->event_log[i].from_state=(uint8_t)s->state;
    s->event_log[i].to_state=(uint8_t)ns;
    strncpy(s->event_log[i].reason,r,23); s->event_log[i].reason[23]=0;
    s->log_head=(s->log_head+1)%EVENT_LOG_SIZE; if(s->log_count<EVENT_LOG_SIZE)s->log_count++;
    printf("[FSM %.2f] %d->%d %s\n",t,(int)s->state,(int)ns,r);
    s->state=ns;
}
static void upd_soc(FsmState_t_struct*s,float Is,float Vb,float dt){
    s->SOC -= (Is*Vb*dt)/(STOR_CAP_AH*3600.0f*V_NOM_V*ETA_DISCHARGE);
    if(s->SOC<SOC_MIN) s->SOC=SOC_MIN;
    if(s->SOC>1.0f)    s->SOC=1.0f;
}
static bool sens_ok(const Sensors_t*s){
    return s->sensor_valid && s->V_bus>=0&&s->V_bus<=20 && s->V_pv>=0&&s->V_pv<=20
        && s->I_src>=-0.5f&&s->I_src<=5.5f && s->I_load>=-0.5f&&s->I_load<=5.5f;
}
const char*fsm_state_name(FsmState_t s){
    static const char*n[]={"BLACKOUT","AUTH_WAIT","SELF_CHECK","SOFT_START",
    "DWELL","CONNECT_PV","RESTORE","NORMAL","FAULT","LOCKOUT"};
    return((int)s>=0&&(int)s<10)?n[(int)s]:"?";
}
const char*fsm_fault_name(FaultCode_t f){
    static const char*n[]={"NONE","OC","I2T","OV","SENSOR","SOC","SS_TMO","SHORT","MISMATCH","SWITCH","SENSOR_FROZEN"};
    return((int)f>=0&&(int)f<=10)?n[(int)f]:"?";
}
