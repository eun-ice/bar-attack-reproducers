#!/usr/bin/env bash
# Runs every scenario in tools/StartScripts/ headless against one engine, several in parallel.
#
#   ./run-matrix.sh <spring-headless> <label> [parallel=4]
#
# Output: results/<label>/<scenario>.{log,infolog.txt,results.txt}, one DATA_DIR per parallel slot.
set -uo pipefail
engine=$1
label=$2
par=${3:-4}
here=$(cd "$(dirname "$0")" && pwd)
export OUT_DIR=$here/results/$label
mkdir -p "$OUT_DIR"

scenario_timeout() {
	case $1 in
		mship_geo*) echo 400 ;;
		corcom_*) echo 120 ;;
		*) echo 150 ;;
	esac
}
export -f scenario_timeout
export here engine label

ls "$here"/tools/StartScripts/startscript_*.txt | grep -v lof_probe | sed 's/.*startscript_//; s/\.txt$//' \
	| xargs -P "$par" -I{} bash -c '
		s={}
		slot=$(( $(echo "$s" | cksum | cut -d" " -f1) % 97 ))
		DATA_DIR=$here/data-matrix/$label/$s "$here/run.sh" "$engine" "$here/tools/StartScripts/startscript_$s.txt" "$s" "$(scenario_timeout "$s")" >/dev/null 2>&1
		echo "done $s"'
echo "matrix $label done"
