#!/usr/bin/env bash
# Re-cuts the recorded scenarios from the raw OBS captures and prepends a 2 s still of the
# end state, so GitHub's video poster shows the result.
#
#   make-previews.sh <raw-dir> [out-dir]
#
# <raw-dir> holds <label>.mp4 (symlinks to the OBS captures). The engine logs
# (<label>-engine.log) next to this script's videos give the sim timing; the Awards screen
# time per label (frame 820) was read off a scene-change scan of the raw capture.
set -euo pipefail

raw=$1
videos=$HOME/Projects/bar/demos/close-in-videos
out=${2:-$videos/preview}
mkdir -p "$out"

declare -A AWARDS=(
	[rock-maneuver-before]=39.8 [rock-holdpos-before]=38.8 [wall-banthas-before]=38.8 [wall-fortifications-before]=46.7
	[rock-maneuver-after]=47.4 [rock-holdpos-after]=47.5 [wall-banthas-after]=47.0 [wall-fortifications-after]=47.0
)

secs() { python3 -c "h,m,s='$1'.split(':'); print(int(h)*3600+int(m)*60+float(s))"; }

build() {
	local lbl=$1 start=$2 end=$3 still=$4 crf=$5
	ffmpeg -hide_banner -loglevel error -y -ss "$still" -i "$raw/$lbl.mp4" -frames:v 1 -vf scale=1920:-2 "$out/$lbl-end.png"
	ffmpeg -hide_banner -loglevel error -y \
		-loop 1 -framerate 30 -t 2 -i "$out/$lbl-end.png" \
		-f lavfi -t 2 -i anullsrc=r=48000:cl=stereo \
		-i "$raw/$lbl.mp4" \
		-filter_complex "[0:v]format=yuv420p,setsar=1,drawtext=text='end of run':fontsize=56:fontcolor=white:borderw=4:bordercolor=black:x=(w-text_w)/2:y=60[v0];[2:v]trim=start=$start:end=$end,setpts=PTS-STARTPTS,scale=1920:-2,setsar=1,format=yuv420p[v2];[2:a]atrim=start=$start:end=$end,asetpts=PTS-STARTPTS[a2];[v0][1:a][v2][a2]concat=n=2:v=1:a=1[v][a]" \
		-map "[v]" -map "[a]" -c:v libx264 -preset medium -crf "$crf" -pix_fmt yuv420p -c:a aac -b:a 96k -movflags +faststart \
		"$out/$lbl-preview.mp4"
	printf "%-28s start=%6.2f end=%6.2f still=%6.2f -> %6.2f s %5.2f MB\n" "$lbl" "$start" "$end" "$still" \
		"$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out/$lbl-preview.mp4")" \
		"$(stat -c %s "$out/$lbl-preview.mp4" | awk '{print $1/1048576}')"
}

for lbl in "${!AWARDS[@]}"; do
	log=$videos/$lbl-engine.log
	t_result=$(secs "$(grep -m1 'ATTACK_OBSTACLE_RESULT' "$log" | sed 's/^\[t=\([0-9:.]*\)\].*/\1/')")
	t_frame1=$(secs "$(grep -m1 'SCENARIO_READY' "$log" | sed 's/^\[t=\([0-9:.]*\)\].*/\1/')")
	aw=${AWARDS[$lbl]}
	# frame 1 .. frame 800 from the log, plus 20 frames to the game over at 820
	start=$(python3 -c "print(f'{$aw-($t_result-$t_frame1+0.67)+0.15:.2f}')")
	end=$(python3 -c "print(f'{$aw-0.15:.2f}')")
	still=$(python3 -c "print(f'{$aw-0.4:.2f}')")
	build "$lbl" "$start" "$end" "$still" 24
done

# Rocko: no game over; game starts at the loading->map transition, keep until 3.5 s after frame 840
build rocko-attack-after 20.5 51.9 50.9 25

sha256sum "$out"/*-preview.mp4 | awk '{print $1, $2}' > "$out/SHA256SUMS.txt"
