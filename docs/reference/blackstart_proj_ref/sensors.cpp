// sensors.cpp - ESP32 ADC sensor driver
// ACS712 + 0-25V module readings with 16x oversampling and IIR filter
#include "sensors.h"
#include <Arduino.h>
#include <esp_adc_cal.h>

static esp_adc_cal_characteristics_t adc_chars;
static float iir_vbus=0, iir_vpv=0, iir_isrc=0, iir_iload=0;
static bool calibrated = false;
static float isrc_offset_adc = ACS_OFFSET_ADC;
static float iload_offset_adc = ACS_OFFSET_ADC;

void sensors_init() {
    analogReadResolution(12);
    analogSetAttenuation(ADC_11db);
    esp_adc_cal_characterize(ADC_UNIT_1, ADC_ATTEN_DB_11,
        ADC_WIDTH_BIT_12, 1100, &adc_chars);
    iir_vbus=iir_vpv=iir_isrc=iir_iload=0.0f;
    calibrated=false;
}

void sensors_calibrate_offsets(FsmState_t_struct* s) {
    // Call with all loads OFF, source disconnected
    // Average 64 samples to find ACS712 zero offset
    float sum_src=0, sum_load=0;
    for(int i=0;i<64;i++){
        sum_src  += analogReadMilliVolts(PIN_ISRC)  / 1000.0f;
        sum_load += analogReadMilliVolts(PIN_ILOAD) / 1000.0f;
        delayMicroseconds(200);
    }
    isrc_offset_adc  = sum_src  / 64.0f;
    iload_offset_adc = sum_load / 64.0f;
    s->I_src_offset  = (isrc_offset_adc  - ACS_OFFSET_V*ACS_DIV_RATIO) / ACS_GAIN_ADC;
    s->I_load_offset = (iload_offset_adc - ACS_OFFSET_V*ACS_DIV_RATIO) / ACS_GAIN_ADC;
    calibrated = true;
    Serial.printf("[CAL] I_src_off=%.3fA I_load_off=%.3fA\n",
        s->I_src_offset, s->I_load_offset);
}

float read_voltage(int pin) {
    uint32_t sum=0;
    for(int i=0;i<ACS_OVERSAMPLE;i++) sum+=analogReadMilliVolts(pin);
    float v_adc = (sum/(float)ACS_OVERSAMPLE)/1000.0f;
    return v_adc / VSENS_DIV;  // un-divide the 1/5 divider
}

float read_current(int pin, float offset_adc_v) {
    uint32_t sum=0;
    for(int i=0;i<ACS_OVERSAMPLE;i++) sum+=analogReadMilliVolts(pin);
    float v_adc = (sum/(float)ACS_OVERSAMPLE)/1000.0f;
    return (v_adc - offset_adc_v) / ACS_GAIN_ADC;
}

void sensors_read(Sensors_t* out) {
    float vbus_raw  = read_voltage(PIN_VBUS);
    float vpv_raw   = read_voltage(PIN_VPV);
    float isrc_raw  = read_current(PIN_ISRC,  isrc_offset_adc);
    float iload_raw = read_current(PIN_ILOAD, iload_offset_adc);

    // IIR filter (first-order, matches MATLAB p.filt.alpha_sens)
    iir_vbus  += IIR_ALPHA*(vbus_raw  - iir_vbus);
    iir_vpv   += IIR_ALPHA*(vpv_raw   - iir_vpv);
    iir_isrc  += IIR_ALPHA*(isrc_raw  - iir_isrc);
    iir_iload += IIR_ALPHA*(iload_raw - iir_iload);

    out->V_bus  = iir_vbus;
    out->V_pv   = iir_vpv;
    out->I_src  = iir_isrc;
    out->I_load = iir_iload;

    // Sensor validity: frozen detection done in protection.cpp
    out->sensor_valid = (iir_vbus>=0) && (iir_vpv>=0) &&
                        (iir_isrc>=-1.0f) && (iir_iload>=-1.0f);
}
