// telemetry.cpp - Serial CSV telemetry (matches MATLAB p.telem.format)
// Format: t_ms,state,vbus,vpv,isrc,iload,soc,duty,load_mask,fault
#include "telemetry.h"
#include <Arduino.h>

void telem_init() {
    Serial.begin(TELEM_BAUD);
    // Print header
    delay(100);
    Serial.println("t_ms,state,vbus,vpv,isrc,iload,soc,duty,load_mask,fault");
}

void telem_print(uint32_t t_ms, const FsmState_t_struct* s, const Sensors_t* sens, const Gates_t* g) {
    Serial.printf("%lu,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%d,%d\n",
        (unsigned long)t_ms,
        (int)s->state,
        sens->V_bus, sens->V_pv,
        sens->I_src, sens->I_load,
        s->SOC,
        g->src_duty,
        (int)g->load_mask,
        (int)s->fault_latched
    );
}
