#!/usr/bin/env bash
# Cuts one recorded scenario video to "map appears .. end state" and prepends a 2 s still of
# the end state (like make-previews.sh). Cut points:
#   start = first strong scene change in the first 25 s (loading screen -> map)
#   end   = start + (t_result - t_load from <label>-engine.log) + tail
#           tail = seconds between the result line and the game over / engine stop
#
#   make-preview-auto.sh <label> <result-regex> <tail-seconds> [out-dir] [crf]
#
# e.g. make-preview-auto.sh rock-maneuver-after ATTACK_OBSTACLE_RESULT 0.67   (game over 20 frames later)
#      make-preview-auto.sh mship-geo-far-after "MSHIP_GEO_RESULT frame=1800" 1.0
#      make-preview-auto.sh corcom-ticks-after CORCOM_TICK_STALL_RESULT 3.0     (engine stopped 6 s later)
# Check <label>-start.png / <label>-end.png in the out dir.
set -euo pipefail

lbl=$1
regex=$2
tail_s=$3
videos=$HOME/Projects/bar/demos/close-in-videos
out=${4:-$videos/preview}
crf=${5:-24}
src=$videos/$lbl.mp4
log=$videos/$lbl-engine.log
mkdir -p "$out"

secs() { python3 -c "h,m,s='$1'.split(':'); print(int(h)*3600+int(m)*60+float(s))"; }
# the map appears when the client reports "finished loading"; frame 1 follows after the
# start countdown (0 s with gamestartdelay=0, otherwise a few seconds)
t_load=$(secs "$(grep -m1 'finished loading and is now ingame' "$log" | sed 's/^\[t=\([0-9:.]*\)\].*/\1/')")
t_result=$(secs "$(grep -E "$regex" "$log" | tail -1 | sed 's/^\[t=\([0-9:.]*\)\].*/\1/')")
# loading screen -> map: the last strong scene change that still leaves room for the run
# (the loading screen itself changes its tip picture, and the map appears with a short fade)
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$src")
latest=$(python3 -c "print($dur - ($t_result - $t_load) - $tail_s)")
first=$(ffprobe -v error -f lavfi -i "movie=$src,select=gt(scene\,0.3)" -show_entries frame=pts_time -of csv=p=0 \
	| awk -F, -v lim="$latest" '$1 < lim && $1 < 60 { t = $1 } END { if (t != "") print t }')
[[ -n "$first" ]] || { echo "no loading->map transition found in $src" >&2; exit 1; }
# clamp to the video (a run stopped by the recorder ends a few seconds after the result line)
t_end=$(python3 -c "print(min($first + ($t_result - $t_load) + $tail_s, $dur - 0.3))")
start=$(python3 -c "print(f'{$first+0.5:.2f}')")
end=$(python3 -c "print(f'{$t_end-0.15:.2f}')")
still=$(python3 -c "print(f'{$t_end-0.4:.2f}')")

ffmpeg -hide_banner -loglevel error -y -ss "$start" -i "$src" -frames:v 1 -vf scale=960:-2 "$out/$lbl-start.png"
ffmpeg -hide_banner -loglevel error -y -ss "$still" -i "$src" -frames:v 1 -vf scale=1920:-2 "$out/$lbl-end.png"
ffmpeg -hide_banner -loglevel error -y \
	-loop 1 -framerate 30 -t 2 -i "$out/$lbl-end.png" \
	-f lavfi -t 2 -i anullsrc=r=48000:cl=stereo \
	-i "$src" \
	-filter_complex "[0:v]format=yuv420p,setsar=1,drawtext=text='end of run':fontsize=56:fontcolor=white:borderw=4:bordercolor=black:x=(w-text_w)/2:y=60[v0];[2:v]trim=start=$start:end=$end,setpts=PTS-STARTPTS,scale=1920:-2,setsar=1,format=yuv420p[v2];[2:a]atrim=start=$start:end=$end,asetpts=PTS-STARTPTS[a2];[v0][1:a][v2][a2]concat=n=2:v=1:a=1[v][a]" \
	-map "[v]" -map "[a]" -c:v libx264 -preset medium -crf "$crf" -pix_fmt yuv420p -c:a aac -b:a 96k -movflags +faststart \
	"$out/$lbl-preview.mp4"
printf "%-24s first=%6.2f start=%6.2f end=%6.2f still=%6.2f -> %6.2f s %5.2f MB\n" "$lbl" "$first" "$start" "$end" "$still" \
	"$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out/$lbl-preview.mp4")" \
	"$(stat -c %s "$out/$lbl-preview.mp4" | awk '{print $1/1048576}')"
