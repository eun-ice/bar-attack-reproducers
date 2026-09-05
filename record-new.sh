#!/usr/bin/env bash
# Records the re-done rock maneuver "after" video and the before/after videos of the two
# reproducers added on 2026-09-05 (commander vs Ticks, missile cruisers vs plateau geo).
#
#   ./record-new.sh [before-spring] [after-spring]
#
# before = master build, after = #3241 stacked on #3328 (engines/ from build-both.sh).
# Output: ~/Projects/bar/demos/close-in-videos/<label>.mp4 (+ -discord.mp4, -engine.log)
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
record=$HOME/Projects/bar/demos/aim-stall-videos/record-reproducer.sh
maps=$HOME/Projects/bar/bar-dev/data/maps
before=${1:-$here/../engines/master/spring}
after=${2:-$here/../engines/pr3242/spring}
export BAR_OUTPUT_DIR=$HOME/Projects/bar/demos/close-in-videos
datadirs=${BAR_RECORD_DATA_ROOT:-$here/data-record}
mkdir -p "$BAR_OUTPUT_DIR" "$datadirs"

run() {
	local overlay=$1 script=$2 map=$3 regex=$4 label=$5 engine=$6
	echo "=== $label ($(date +%H:%M:%S))"
	if [[ -s "$BAR_OUTPUT_DIR/$label.mp4" ]]; then
		echo "exists, skipping"
		return
	fi
	BAR_ENGINE=$engine BAR_DATA_DIR=$datadirs/$label BAR_POST_SECONDS=${BAR_POST_SECONDS:-8} \
		"$record" "$overlay" "$script" "$maps/$map" "$regex" "$label" || echo "FAILED: $label"
	sleep 3
}

# rock maneuver with the stacked engine (replaces rock-maneuver-after from the first recording)
run "$here" startscript_attack_obstacle_rock_maneuver.txt all_that_glitters_v2.2.3.sd7 ATTACK_OBSTACLE_RESULT rock-maneuver-after "$after"
for variant in before after; do
	engine=${!variant}
	BAR_POST_SECONDS=6 run "$here/corcom-overlay" startscript_corcom_tick_attack_stall.txt all_that_glitters_v2.2.3.sd7 CORCOM_TICK_STALL_RESULT corcom-ticks-$variant "$engine"
	BAR_POST_SECONDS=4 run "$here/mship-overlay" startscript_mship_geo_far.txt supreme_isthmus_v2.1.sd7 "MSHIP_GEO_RESULT frame=1800" mship-geo-far-$variant "$engine"
	BAR_POST_SECONDS=4 run "$here/mship-overlay" startscript_mship_geo_close.txt supreme_isthmus_v2.1.sd7 "MSHIP_GEO_RESULT frame=1800" mship-geo-close-$variant "$engine"
done
echo "=== all done ($(date +%H:%M:%S))"
