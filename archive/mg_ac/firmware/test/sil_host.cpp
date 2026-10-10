// sil_host.cpp - PC build of the firmware core for the SIL test.
// Reads MATLAB's "M" lines (file or stdin), runs the SAME controller.cpp and
// protocol.cpp as the ESP32, prints the "C" lines. Compare with MATLAB's.
#include <stdio.h>
#include <string.h>
#include "controller.h"
#include "protocol.h"

int main(int argc, char** argv) {
    FILE* f = (argc > 1) ? fopen(argv[1], "r") : stdin;
    if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    static char line[1024], reply[512];
    CtrlState st; ctrl_init(st); Meas m; Out o;
    long n = 0;
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\r\n")] = 0;
        if (line[0] == 'R') { ctrl_init(st); continue; }
        if (!proto_parse_meas(line, m)) { fprintf(stderr, "parse error line %ld\n", n + 1); return 3; }
        ctrl_step(st, m, o);
        proto_format_cmd(reply, sizeof reply, m.seq, o);
        puts(reply); n++;
    }
    return 0;
}
