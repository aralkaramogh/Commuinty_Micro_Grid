// node.h - node controller core (load node H1/H2/CL and solar+BESS node SB).
// MATLAB twins: nodes/node_load_step.m, nodes/node_sb_step.m (SIL keeps them equal).
#pragma once
#include <stddef.h>
#include <stdint.h>
#include "config_node.h"

struct LoadIn  { long seq; int valid, enable, flex_allow; double v, i, p_load, q_load, p_pv, q_pv; uint32_t card_uid; };
struct LoadOut { int tie, flex, hstate, strikes, comm_lost; double e_imp, e_exp; };
struct LoadSt  { int enabled, flex_allow; long n_nocmd; int hstate, n_oc, strikes, n_healthy, retry, tie, flex;
                 double e_imp, e_exp; };
struct SbIn    { long seq; int valid; double p_set, q_set; int sync; double soc, p_bess, q_bess;
                 int bess_status; double v_c, f_mg, p_cpv; };
struct SbOut   { double p, q; int sync, clamped, comm_lost; };
struct SbSt    { long n_nocmd; double p_cmd, q_cmd; int sync_cmd; };

void load_init(LoadSt& st);
void load_step(LoadSt& st, const LoadIn& x, LoadOut& r);
void sb_init(SbSt& st);
void sb_step(SbSt& st, const SbIn& x, SbOut& r);

bool parse_L(const char* line, LoadIn& x);
bool parse_B(const char* line, SbIn& x);
int  format_l(char* buf, size_t len, const LoadIn& x, const LoadOut& r);
int  format_b(char* buf, size_t len, const SbIn& x, const SbOut& r);
