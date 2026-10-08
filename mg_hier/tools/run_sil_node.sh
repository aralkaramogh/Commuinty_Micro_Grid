#!/usr/bin/env bash
# run_sil_node.sh - SIL equivalence for the NODE firmware: replay every line MATLAB
# sent to each node (results/logs/*_in.txt) through the real C++ (node.cpp) and
# diff the replies with MATLAB's virtual node (results/logs/*_out.txt).
# Usage (from mg_hier/):  bash tools/run_sil_node.sh     (needs g++)
set -u
cd "$(dirname "$0")/.."
mkdir -p results/logs
g++ -std=c++17 -O2 -Wall -Wextra -Ifirmware_node/mg_node firmware_node/mg_node/node.cpp \
    firmware_node/test/sil_node_host.cpp -o results/logs/sil_node_host || exit 1
fail=0; total=0; files=0
for IN in results/logs/*_in.txt; do
  name=$(basename "$IN" _in.txt); OUT="results/logs/${name}_out.txt"
  ./results/logs/sil_node_host "$IN" > "results/logs/${name}_cpp.txt" || { echo "$name: RUN ERROR"; fail=1; continue; }
  n=$(wc -l < "$OUT"); total=$((total+n)); files=$((files+1))
  d=$(diff <(tr -d '\r' < "$OUT") "results/logs/${name}_cpp.txt" | grep -c '^>')
  if [ "$d" -ne 0 ]; then echo "$name: $n lines, $d MISMATCHED"; fail=1; fi
done
echo "node SIL: $files node logs, $total replies compared"
[ $fail -eq 0 ] && echo "SIL PASS (0 mismatches)" || echo "SIL FAIL"
exit $fail
