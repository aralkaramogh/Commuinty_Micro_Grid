// main.cpp  -  ESP32 Black-Start Controller (Arduino framework, FreeRTOS)
// Aarambh Hackathon #34 - DC Solar Microgrid Black-Start
//
// SAFETY: All gate pins are driven LOW before setup() by the pin-init code.
//         Hardware watchdog (TWDT) enabled with 5s timeout.
//         fail-safe: WDT reset drives all gates LOW on reboot (see fsm_init).
//
// Tasks:
//   fastTask  @ 1 kHz : sensor read, PWM update, protection fast-path
//   fsmTask   @ 100 Hz: supervisory FSM tick
//   telemTask @ 10 Hz : serial CSV telemetry
//   rfidTask  @ 5 Hz  : RFID poll

#include <Arduino.h>
#include <esp_task_wdt.h>
#include "config.h"
#include "fsm.h"
#include "sensors.h"
#include "protection.h"
#include "restoration.h"
#include "pwm_soft_start.h"
#include "auth_rfid.h"
#include "telemetry.h"

/* ---- Shared state (protected by critical sections) --------------- */
static FsmState_t_struct g_fsm;
static Sensors_t         g_sens;
static Gates_t           g_gates;
static portMUX_TYPE      g_mux = portMUX_INITIALIZER_UNLOCKED;

/* ---- Physical gate pins ------------------------------------------ */
static const int GATE_PINS[6] = {
    PIN_SRC_SW, PIN_PV_SW,
    PIN_LOAD1, PIN_LOAD2, PIN_LOAD3, PIN_LOAD4
};
#define N_GATE_PINS 6

static void gates_all_off() {
    for(int i=0;i<N_GATE_PINS;i++) digitalWrite(GATE_PINS[i], LOW);
    ledcWrite(0, 0);  // PWM duty = 0
}

static void apply_gates(const Gates_t* g) {
    // Source switch: PWM soft-start via LEDC
    pwm_set_duty(PIN_SRC_SW, g->src_duty);
    // PV switch: digital
    digitalWrite(PIN_PV_SW,  g->pv_sw ? HIGH : LOW);
    // Load switches: 4-bit mask
    digitalWrite(PIN_LOAD1, (g->load_mask & 0x01) ? HIGH : LOW);
    digitalWrite(PIN_LOAD2, (g->load_mask & 0x02) ? HIGH : LOW);
    digitalWrite(PIN_LOAD3, (g->load_mask & 0x04) ? HIGH : LOW);
    digitalWrite(PIN_LOAD4, (g->load_mask & 0x08) ? HIGH : LOW);
    // Status LED: ON when in normal operation
    digitalWrite(PIN_LED, (g->load_mask != 0) ? HIGH : LOW);
}

/* ---- FreeRTOS Tasks ---------------------------------------------- */
static void fastTask(void* pv) {
    (void)pv;
    TickType_t xLast = xTaskGetTickCount();
    while(1){
        vTaskDelayUntil(&xLast, pdMS_TO_TICKS(1)); // 1 kHz
        esp_task_wdt_reset();
        Sensors_t local_sens;
        sensors_read(&local_sens);
        taskENTER_CRITICAL(&g_mux);
        g_sens = local_sens;
        taskEXIT_CRITICAL(&g_mux);
    }
}

static void fsmTask(void* pv) {
    (void)pv;
    float t_s = 0.0f;
    TickType_t xLast = xTaskGetTickCount();
    while(1){
        vTaskDelayUntil(&xLast, pdMS_TO_TICKS((uint32_t)TS_FSM_MS));
        t_s += TS_FSM_MS / 1000.0f;

        Sensors_t local_sens;
        taskENTER_CRITICAL(&g_mux); local_sens = g_sens; taskEXIT_CRITICAL(&g_mux);

        Gates_t local_gates;
        fsm_tick(t_s, &local_sens, &g_fsm, &local_gates);
        apply_gates(&local_gates);

        taskENTER_CRITICAL(&g_mux); g_gates = local_gates; taskEXIT_CRITICAL(&g_mux);
    }
}

static void telemTask(void* pv) {
    (void)pv;
    uint32_t t_ms = 0;
    TickType_t xLast = xTaskGetTickCount();
    while(1){
        vTaskDelayUntil(&xLast, pdMS_TO_TICKS((uint32_t)TELEM_PERIOD_MS));
        t_ms += (uint32_t)TELEM_PERIOD_MS;
        Sensors_t ls; Gates_t lg;
        taskENTER_CRITICAL(&g_mux); ls=g_sens; lg=g_gates; taskEXIT_CRITICAL(&g_mux);
        telem_print(t_ms, &g_fsm, &ls, &lg);
    }
}

static void rfidTask(void* pv) {
    (void)pv;
    TickType_t xLast = xTaskGetTickCount();
    while(1){
        vTaskDelayUntil(&xLast, pdMS_TO_TICKS(200)); // 5 Hz
        rfid_poll(&g_fsm);
    }
}

/* ================================================================== */
void setup() {
    /* FIRST: drive all gate pins LOW before anything else */
    for(int i=0;i<N_GATE_PINS;i++){
        pinMode(GATE_PINS[i], OUTPUT);
        digitalWrite(GATE_PINS[i], LOW);
    }
    pinMode(PIN_LED,    OUTPUT); digitalWrite(PIN_LED,    LOW);
    pinMode(PIN_BUZZER, OUTPUT); digitalWrite(PIN_BUZZER, LOW);

    /* Init subsystems */
    telem_init();                         // Serial 115200
    sensors_init();
    pwm_init(PIN_SRC_SW, PWM_FREQ_HZ);   // LEDC channel 0, duty=0
    rfid_init();

    /* Hardware watchdog: 5 s timeout -> resets ESP32 -> gates default OFF */
    esp_task_wdt_config_t wdt_cfg = {
        .timeout_ms = (uint32_t)(WDT_TIMEOUT_S * 1000),
        .idle_core_mask = (1 << 0),
        .trigger_panic = true
    };
    esp_task_wdt_reconfigure(&wdt_cfg);

    /* FSM initialise - sets all gate outputs to 0 in struct */
    fsm_init(&g_fsm);
    g_gates = {0.0f, false, 0};

    Serial.printf("[BOOT] DC Microgrid Black-Start v%d.%d (%s)\n",
        FW_VERSION_MAJOR, FW_VERSION_MINOR, FW_BUILD_DATE);
    Serial.printf("[BOOT] V_nom=%.1fV Config-%s PWM=%dHz\n",
        V_NOM_V, BUS_CONFIG_A?"A":"B", PWM_FREQ_HZ);

    /* Sensor calibration (all loads off at boot) */
    sensors_calibrate_offsets(&g_fsm);

    /* Create FreeRTOS tasks */
    xTaskCreatePinnedToCore(fastTask, "fast", 4096, NULL, 5, NULL, 1);
    xTaskCreatePinnedToCore(fsmTask,  "fsm",  8192, NULL, 4, NULL, 1);
    xTaskCreatePinnedToCore(telemTask,"telem",4096, NULL, 2, NULL, 0);
    xTaskCreatePinnedToCore(rfidTask, "rfid", 4096, NULL, 3, NULL, 0);
}

void loop() {
    // All work is in FreeRTOS tasks; loop() sleeps
    vTaskDelay(pdMS_TO_TICKS(1000));
}
