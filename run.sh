#!/usr/bin/env bash
# Runs one reproducer scenario headless in an isolated data dir and prints its result lines.
#
#   ./run.sh <spring-headless> <startscript> <label> [timeout-seconds]
#
# The gadgets in luarules/gadgets/ are linked into the BAR checkout (BAR_CHECKOUT) for the
# run; the checkout is exposed to the engine as games/Beyond-All-Reason.sdd inside DATA_DIR.
# Output: <out>/<label>.log (engine stdout), <out>/<label>.infolog.txt, <out>/<label>.results.txt
set -euo pipefail

engine=$1
script=$2
label=$3
timeout_s=${4:-100}

here=$(cd "$(dirname "$0")" && pwd)
bar="${BAR_CHECKOUT:-/home/aron/Projects/bar/Beyond-All-Reason}"
maps="${BAR_MAPS_DIR:-/home/aron/Projects/bar/bar-dev/data/maps}"
data="${DATA_DIR:-$here/data}"
out="${OUT_DIR:-$here/results}"
mkdir -p "$data/games" "$data/maps" "$out"

[[ -e "$data/games/Beyond-All-Reason.sdd" ]] || ln -s "$bar" "$data/games/Beyond-All-Reason.sdd"
for m in all_that_glitters_v2.2.3.sd7 quicksilver_remake_1.24.sd7 supreme_isthmus_v2.1.sd7; do
	[[ -e "$data/maps/$m" ]] || ln -s "$maps/$m" "$data/maps/$m"
done
for g in "$here"/luarules/gadgets/*.lua; do
	ln -sfn "$g" "$bar/luarules/gadgets/$(basename "$g")"
done

rm -f "$data/infolog.txt"
timeout --signal=INT "$timeout_s" "$engine" --isolation --write-dir "$data" "$script" >"$out/$label.log" 2>&1 || true
cp "$data/infolog.txt" "$out/$label.infolog.txt" 2>/dev/null || true
# the stdout log has every Echo line; the infolog copy can miss the last ones of a run that is
# stopped by the timeout
grep -h "ATTACK_OBSTACLE_\(SCENARIO_READY\|LINE\|VALIDATION_START\|RESULT\|DIAG\|WALL\|BLOCKER\)\|ROCKO_SLOPE_STALL_\(SCENARIO_READY\|RESULT\)\|CORCOM_TICK_STALL_\(SCENARIO_READY\|RESULT\|WEAPONS\)\|MSHIP_GEO_\(SCENARIO_READY\|ATTACK_ISSUED\|RESULT\|TARGET_DESTROYED\)\|Error\|error:" "$out/$label.log" \
	| grep -v "readlink()\|removed ceg_test" \
	| sed -E 's/^(\[[^]]*\])+ //' | tee "$out/$label.results.txt"
