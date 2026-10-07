#!/usr/bin/env bash
# run_sil.sh - SIL equivalence: replay MATLAB "M" frames through the real
# firmware C++ (controller.cpp + protocol.cpp) and diff the "C" replies.
# Usage (from mg_ac/):  bash tools/run_sil.sh      (needs g++)
set -u
cd "$(dirname "$0")/.."
mkdir -p results/logs
g++ -std=c++17 -O2 -Wall -DSIL_HOST -Ifirmware/include firmware/src/controller.cpp \
    firmware/src/protocol.cpp firmware/test/sil_host.cpp -o results/logs/sil_host || exit 1
fail=0; total=0
for M in results/logs/*_M.txt; do
  name=$(basename "$M" _M.txt); C="results/logs/${name}_C.txt"
  ./results/logs/sil_host "$M" > "results/logs/${name}_C_cpp.txt" || { echo "$name: RUN ERROR"; fail=1; continue; }
  n=$(wc -l < "$C"); total=$((total+n))
  d=$(diff <(tr -d '\r' < "$C") "results/logs/${name}_C_cpp.txt" | grep -c '^>')
  if [ "$d" -eq 0 ]; then echo "$name: $n ticks, 0 mismatches"; else echo "$name: $n ticks, $d MISMATCHED lines"; fail=1; fi
done
echo "TOTAL ticks compared: $total"
[ $fail -eq 0 ] && echo "SIL PASS" || echo "SIL FAIL"
exit $fail
