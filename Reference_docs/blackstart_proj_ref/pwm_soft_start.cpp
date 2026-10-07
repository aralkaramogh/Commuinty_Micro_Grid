// pwm_soft_start.cpp - LEDC PWM for soft-start (ESP32 LEDC peripheral)
#include "pwm_soft_start.h"
#include <Arduino.h>

#define LEDC_CHANNEL 0
#define LEDC_BITS    10  // 10-bit resolution = 1024 steps

void pwm_init(int pin, uint32_t freq_hz) {
    ledcSetup(LEDC_CHANNEL, freq_hz, LEDC_BITS);
    ledcAttachPin(pin, LEDC_CHANNEL);
    ledcWrite(LEDC_CHANNEL, 0);  // Start at 0 duty (SAFE)
}

void pwm_set_duty(int pin, float duty_0_1) {
    (void)pin;  // channel bound to pin in init
    if(duty_0_1 < 0.0f) duty_0_1=0.0f;
    if(duty_0_1 > 1.0f) duty_0_1=1.0f;
    uint32_t raw = (uint32_t)(duty_0_1 * ((1<<LEDC_BITS)-1));
    ledcWrite(LEDC_CHANNEL, raw);
}
