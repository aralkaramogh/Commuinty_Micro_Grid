// lcd_test.ino - basic 16x2 I2C LCD test (no microgrid code).
// 1) scans the I2C bus and prints every address found (Serial Monitor, 115200 baud)
// 2) shows two lines and a counter on the LCD at the first address found.
// Pins match mg_node_lcd: ESP32-S3 SDA 16 / SCL 17, ESP32-WROOM SDA 32 / SCL 13.
// Library: "LiquidCrystal I2C" (Frank de Brabander / Marco Schwartz) - same as mg_node_lcd.
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

#if defined(CONFIG_IDF_TARGET_ESP32S3)
#define LCD_SDA 16
#define LCD_SCL 17
#else
#define LCD_SDA 32
#define LCD_SCL 13
#endif

LiquidCrystal_I2C *lcd = nullptr;
uint8_t addr = 0;

void setup() {
  Serial.begin(115200);
  delay(1500);                       // S3 USB-CDC: give the Serial Monitor time to attach
  Serial.printf("\nLCD test. SDA=%d SCL=%d\n", LCD_SDA, LCD_SCL);
  Wire.begin(LCD_SDA, LCD_SCL);
  Wire.setClock(100000);
  int n = 0;
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      Serial.printf("  found I2C device at 0x%02X\n", a);
      if (!addr) addr = a;
      n++;
    }
  }
  if (n == 0) {
    Serial.println("  NOTHING found -> check wiring (SDA/SCL swapped?), 5V + GND, pins.");
    return;
  }
  lcd = new LiquidCrystal_I2C(addr, 16, 2);
  lcd->init();
  lcd->backlight();
  lcd->setCursor(0, 0); lcd->print("URJA LCD test");
  lcd->setCursor(0, 1); lcd->printf("addr 0x%02X", addr);
  Serial.printf("  LCD started at 0x%02X. If backlight is on but no text: turn the blue contrast pot.\n", addr);
}

void loop() {
  static uint32_t k = 0;
  if (lcd) {
    lcd->setCursor(11, 1);
    lcd->printf("%5lu", (unsigned long)(k++ % 100000));
  }
  delay(500);
}
