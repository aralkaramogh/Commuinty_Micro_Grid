// lcd_check.cpp - compile the LCD sketch on the PC and print its pages for sample inputs
#include "../mg_node_lcd/mg_node_lcd.ino"
int main() {
    setup();
    const char* in[] = {"D,1,1,3450.0,1", "L,1,1,1,1,229.100,6.1000,1400.00,300.00,250.00,0.00,0",
                        "D,2,2,3450.0,4", "B,2,1,0.0,0.0,0,0.780000,3200.00,100.00,0,230.000,49.8400,450.00",
                        "D,3,2,3450.0,3", "L,3,0,1,0,230.000,4.0000,600.00,450.00,0.00,0.00,0"};
    for (int k = 0; k < 6; k++) {
        for (const char* p = in[k]; *p; p++) line[len++] = *p; line[len] = 0;
        // emulate one received line
        len = 0; char buf[256]; snprintf(buf, sizeof buf, "%s", in[k]);
        if (buf[0] == 'D') { parse_D(buf); continue; }
        if (buf[0] == 'L') { LoadIn x; parse_L(buf, x); role = 'L'; load_step(ls, x, lo); li = x; }
        if (buf[0] == 'B') { SbIn x; parse_B(buf, x); role = 'B'; sb_step(bs, x, so); si = x; }
        int np = (d_role == 4) ? 7 : (d_role == 3 ? 4 : 5);
        for (page = 0; page < np; page++) render(false);
    }
    return 0;
}
