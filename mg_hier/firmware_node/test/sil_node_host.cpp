// sil_node_host.cpp - PC build of the node core for the SIL test.
// Reads the "L"/"B" lines MATLAB sent to one node, runs the SAME node.cpp as the
// ESP32, prints the replies. tools/run_sil_node.sh diffs them with MATLAB's.
#include <stdio.h>
#include <string.h>
#include "node.h"

int main(int argc, char** argv) {
    FILE* f = (argc > 1) ? fopen(argv[1], "r") : stdin;
    if (!f) { fprintf(stderr, "cannot open %s\n", argv[1]); return 2; }
    static char line[512], reply[256];
    LoadSt ls; SbSt bs; load_init(ls); sb_init(bs);
    long n = 0; bool pin = false;            // simulated E-stop pin ("S,1" / "S,0" lines)
    while (fgets(line, sizeof line, f)) {
        line[strcspn(line, "\r\n")] = 0; n++;
        if (line[0] == 'S') { pin = (line[2] == '1'); continue; }
        if (line[0] == 'R') { load_init(ls); sb_init(bs); puts("READY"); continue; }
        if (line[0] == 'L') {
            LoadIn x; LoadOut r;
            if (!parse_L(line, x)) { fprintf(stderr, "parse error line %ld\n", n); return 3; }
            load_step(ls, x, r, pin); format_l(reply, sizeof reply, x, r);
        } else if (line[0] == 'B') {
            SbIn x; SbOut r;
            if (!parse_B(line, x)) { fprintf(stderr, "parse error line %ld\n", n); return 3; }
            sb_step(bs, x, r, pin); format_b(reply, sizeof reply, x, r);
        } else { fprintf(stderr, "unknown line %ld\n", n); return 3; }
        puts(reply);
    }
    return 0;
}
