// auth_rfid.cpp - RC522 RFID operator authentication
// Depends: MFRC522 library (miguelbalboa)
#ifndef SIL_TEST_MODE
#include "auth_rfid.h"
#include <MFRC522.h>
#include "config.h"

static MFRC522 mfrc522(PIN_RC522_CS, PIN_RC522_RST);
static uint8_t authorised_uid[7] = {0xAB, 0xCD, 0xEF, 0x01, 0x00, 0x00, 0x00};
static uint8_t authorised_uid_len = 4;

void rfid_init() {
    SPI.begin(PIN_RC522_SCK, PIN_RC522_MISO, PIN_RC522_MOSI, PIN_RC522_CS);
    mfrc522.PCD_Init();
    Serial.println("[RFID] RC522 initialised. Waiting for tag...");
}

void rfid_set_authorised_uid(const uint8_t* uid, uint8_t len) {
    memcpy(authorised_uid, uid, len);
    authorised_uid_len = len;
}

void rfid_poll(FsmState_t_struct* s) {
    if (!mfrc522.PICC_IsNewCardPresent()) return;
    if (!mfrc522.PICC_ReadCardSerial()) return;

    uint8_t* uid = mfrc522.uid.uidByte;
    uint8_t  len = mfrc522.uid.size;

    Serial.printf("[RFID] Tag: ");
    for(int i=0;i<len;i++) Serial.printf("%02X ",uid[i]);
    Serial.println();

    bool match = (len == authorised_uid_len);
    for(int i=0;i<len&&match;i++) match = (uid[i]==authorised_uid[i]);

    fsm_inject_rfid(s, match ? RFID_VALID : RFID_INVALID);
    mfrc522.PICC_HaltA();
    mfrc522.PCD_StopCrypto1();
}
#else
// SIL stub
#include "auth_rfid.h"
void rfid_init(){}
void rfid_poll(FsmState_t_struct* s){(void)s;}
void rfid_set_authorised_uid(const uint8_t* uid, uint8_t len){(void)uid;(void)len;}
#endif
