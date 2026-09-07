#!/usr/bin/env bash
# ./run-all.sh <spring-headless> <label>   -- runs the three variants, prints the RESULT lines
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
for v in destroy queued remove; do
	DATA_DIR="$here/data-$2" "$here/run.sh" "$1" "$here/tools/StartScripts/startscript_$v.txt" "$2_$v" 90 | grep -E 'RESULT|SETUP|TRIGGER |Error|error' || true
done
