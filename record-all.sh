#!/usr/bin/env bash
# Records every close-in scenario with demos/aim-stall-videos/record-reproducer.sh,
# once with the engine before the CommandAI change and once with the new one.
#
#   ./record-all.sh [before-spring] [after-spring]
#
# Output: ~/Projects/bar/demos/close-in-videos/<label>.mp4 (+ -discord.mp4, -engine.log)
set -uo pipefail

here=$(cd "$(dirname "$0")" && pwd)
record=$HOME/Projects/bar/demos/aim-stall-videos/record-reproducer.sh
maps=$HOME/Projects/bar/bar-dev/data/maps
before=${1:-/tmp/claude-1000/-home-aron-Projects-bar/363876ba-4757-4d36-b386-6b658d218051/scratchpad/install-before/spring}
after=${2:-$HOME/Projects/bar/RecoilEngine/build-amd64-linux/install/spring}
export BAR_OUTPUT_DIR=$HOME/Projects/bar/demos/close-in-videos
datadirs=${BAR_RECORD_DATA_ROOT:-/tmp/claude-1000/-home-aron-Projects-bar/363876ba-4757-4d36-b386-6b658d218051/scratchpad/record-data}
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

for variant in before after; do
	engine=${!variant}
	run "$here" startscript_attack_obstacle_rock_maneuver.txt all_that_glitters_v2.2.3.sd7 ATTACK_OBSTACLE_RESULT rock-maneuver-$variant "$engine"
	run "$here" startscript_attack_obstacle_rock_holdpos.txt all_that_glitters_v2.2.3.sd7 ATTACK_OBSTACLE_RESULT rock-holdpos-$variant "$engine"
	run "$here" startscript_attack_obstacle_wall_armbanth.txt quicksilver_remake_1.24.sd7 ATTACK_OBSTACLE_RESULT wall-banthas-$variant "$engine"
	run "$here" startscript_attack_obstacle_wall_armfort.txt quicksilver_remake_1.24.sd7 ATTACK_OBSTACLE_RESULT wall-fortifications-$variant "$engine"
done
BAR_POST_SECONDS=4 run "$here/rocko-overlay" startscript_rocko_slope_attack.txt quicksilver_remake_1.24.sd7 "ROCKO_SLOPE_STALL_RESULT frame=840" rocko-attack-after "$after"
echo "=== all done ($(date +%H:%M:%S))"
