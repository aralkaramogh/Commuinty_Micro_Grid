// protocol.h - text lines over USB serial (see docs/protocol.md)
#pragma once
#include "controller.h"
#include <stddef.h>
bool proto_parse_meas(const char* line, Meas& m);
int  proto_format_cmd(char* buf, size_t len, long seq, const Out& o);
