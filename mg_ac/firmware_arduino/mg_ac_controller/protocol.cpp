// protocol.cpp - parse "M" lines, format "C" lines. Field order must match
// comms/proto_encode_meas.m and comms/proto_encode_cmd.m.
#include "protocol.h"
#include <stdio.h>
#include <stdlib.h>

static bool next_d(const char*& p, double& v) {
    if (*p != ',') return false;
    char* e; v = strtod(p + 1, &e);
    if (e == p + 1) return false;
    p = e; return true;
}

bool proto_parse_meas(const char* line, Meas& m) {
    if (line[0] != 'M') return false;
    const char* p = line + 1;
    double v[23];
    for (int i = 0; i < 23; i++) if (!next_d(p, v[i])) return false;
    m.seq = (long)v[0]; m.t_ms = (long)v[1];
    m.v_grid = v[2]; m.f_grid = v[3]; m.v_c = v[4]; m.f_mg = v[5]; m.dtheta = v[6];
    m.p_pcc = v[7]; m.q_pcc = v[8]; m.p_bess = v[9]; m.q_bess = v[10]; m.soc = v[11];
    m.bess_status = (int)v[12]; m.p_cl = v[13]; m.q_cl = v[14]; m.p_cpv = v[15];
    m.fb = (uint32_t)v[16]; m.card_house = (int)v[17]; m.card_uid = (uint32_t)v[18];
    m.ai_valid = (int)v[19]; m.ai_p = v[20]; m.ai_mask = (uint32_t)v[21]; m.ai_price = v[22];
    for (int k = 0; k < N_HOUSES; k++) {
        if (!next_d(p, m.v_h[k]) || !next_d(p, m.i_h[k]) || !next_d(p, m.p_load[k]) ||
            !next_d(p, m.q_load[k]) || !next_d(p, m.p_pv[k]) || !next_d(p, m.q_pv[k])) return false;
    }
    return (*p == '\0' || *p == '\r' || *p == '\n');
}

int proto_format_cmd(char* buf, size_t len, long seq, const Out& o) {
    int n = snprintf(buf, len, "C,%ld,%lu,%d,%.1f,%.1f,%d,%d,%.3f", seq, (unsigned long)o.bits, o.mode,
                     o.p_set, o.q_set, o.flags, o.ai_status, o.price);
    for (int k = 0; k < N_HOUSES && n > 0 && (size_t)n < len; k++)
        n += snprintf(buf + n, len - n, ",%.4f,%d", o.bal[k], o.hcode[k]);
    return n;
}
