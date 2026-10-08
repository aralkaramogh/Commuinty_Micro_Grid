#include <WiFi.h>
#include <PubSubClient.h>

// ---------- CHANGE THESE ----------
const char* ssid        = "WCE Wi-Fi 6";
const char* password    = "Walchand@123";
const char* mqtt_server = "10.30.23.55";   // Raspberry Pi IP
const int   mqtt_port   = 1883;
const char* DEVICE_ID   = "esp32_1";       // esp32_2 and esp32_3 on the other boards
// ----------------------------------

#define LED_PIN 2   // onboard LED blinks on every publish

WiFiClient espClient;
PubSubClient client(espClient);

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) return;
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
  }
}

void connectMQTT() {
  while (!client.connected()) {
    connectWiFi();
    if (!client.connect(DEVICE_ID)) {
      delay(2000);   // retry
    }
  }
}

void setup() {
  pinMode(LED_PIN, OUTPUT);
  Serial.begin(115200);          // MATLAB talks to the ESP32 on this port
  connectWiFi();
  client.setServer(mqtt_server, mqtt_port);
  client.setBufferSize(512);
}

void loop() {
  connectMQTT();
  client.loop();

  if (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();

    float v, i, p, pf, e;
    // MATLAB sends: V,I,P,PF,Energy
    if (sscanf(line.c_str(), "%f,%f,%f,%f,%f", &v, &i, &p, &pf, &e) == 5) {
      float s = v * i;                              // apparent power (VA)
      float q = sqrt(max(0.0f, s * s - p * p));     // reactive power (VAR)

      char payload[256];
      snprintf(payload, sizeof(payload),
        "{\"voltage\":%.1f,\"current\":%.3f,\"active_power\":%.1f,"
        "\"reactive_power\":%.1f,\"apparent_power\":%.1f,"
        "\"energy\":%.4f,\"pf\":%.2f}",
        v, i, p, q, s, e, pf);

      String topic = String("mg/") + DEVICE_ID + "/data";
      if (client.publish(topic.c_str(), payload)) {
        digitalWrite(LED_PIN, HIGH);
        delay(50);
        digitalWrite(LED_PIN, LOW);
      }
    }
  }
}