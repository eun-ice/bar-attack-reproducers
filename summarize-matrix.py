#!/usr/bin/env python3
"""Summarises results/<label>/*.results.txt for several engine labels side by side.

    ./summarize-matrix.py master pr3242

Per scenario one line per engine with the metrics that decide pass/fail, then a verdict:
  attack_obstacle_*  : per shooter targetHits/moved; stall = moved < 50 and no target hits
  rocko_slope_*      : projectiles fired at the last report
  corcom_*           : stalled flag, projectiles, target alive
  mship_geo_*        : ships that fired (projectiles > 0) at frame 1800
"""
import glob, os, re, sys

here = os.path.dirname(os.path.abspath(__file__))
labels = sys.argv[1:] or ["master", "pr3242"]

def kv(line):
    return dict(re.findall(r"(\w+)=([^\s]+)", line))

def summarize(scenario, lines):
    results = [kv(l) for l in lines if "_RESULT" in l]
    if not results:
        return "no result line", None
    if scenario.startswith("attack_obstacle"):
        parts, stalls, hits = [], 0, 0
        for r in results:
            h, m = int(r["targetHits"]), float(r["moved"])
            parts.append(f"{h}h/{m:.0f}m")
            if h > 0:
                hits += 1
            if m < 50 and h == 0:
                stalls += 1
        if scenario in ("attack_obstacle_wall_armbanth", "attack_obstacle_wall_corkorg"):
            # mobile allies in the way: the shooters must wait, not push into the row
            ok = all(float(r["moved"]) < 5 for r in results)
            return f"moved={[round(float(r['moved'])) for r in results]} hits={hits}", ok
        if scenario.startswith("attack_obstacle_wall"):
            return f"shooters(hits/moved)={' '.join(parts)} hitting={hits}", hits >= 3
        if scenario.startswith("attack_obstacle_friendlyline"):
            return f"shooters(hits/moved)={' '.join(parts)} hitting={hits} stalled={stalls}", None
        return f"shooters(hits/moved)={' '.join(parts)} hitting={hits} stalled={stalls}", stalls == 0
    if scenario.startswith("rocko"):
        rs = [r for r in results if "projectiles" in r]
        if not rs:
            return "no usable result line", None
        r = rs[-1]
        fired = int(r["projectiles"].split("/")[0])
        return f"frame={r['frame']} phase={r.get('phase')} projectiles={r['projectiles']} moved={r['moved']}", fired > 0
    if scenario.startswith("corcom"):
        r = results[-1]
        if r.get("order") == "move":
            return f"order=move moved={r['moved']} dist={r['distToTarget']}", float(r["distToTarget"]) < 50
        return (f"stalled={r['stalled']} moved={r['moved']} dist={r['distToTarget']} projectiles={r['projectiles']} "
                f"targetAlive={r['targetAlive']}"), r["stalled"] == "false" and int(r["projectiles"]) > 0
    if scenario.startswith("mship"):
        last = max(int(r["frame"]) for r in results)
        fin = [r for r in results if int(r["frame"]) == last]
        fired = sum(1 for r in fin if int(r["projectiles"]) > 0)
        moved = [round(float(r["moved"])) for r in fin]
        return f"frame={last} shipsFired={fired}/{len(fin)} moved={moved} tryTarget={[r['tryTarget'] for r in fin]}", fired == len(fin)
    return f"{len(results)} result lines", None

scenarios = sorted({os.path.basename(f)[:-len(".results.txt")]
                    for lb in labels for f in glob.glob(f"{here}/results/{lb}/*.results.txt")})
for s in scenarios:
    print(f"== {s}")
    for lb in labels:
        f = f"{here}/results/{lb}/{s}.results.txt"
        if not os.path.exists(f):
            print(f"  {lb:8s} (not run)")
            continue
        text, ok = summarize(s, open(f).read().splitlines())
        verdict = "PASS" if ok else ("FAIL" if ok is False else "info")
        print(f"  {lb:8s} {verdict:4s} {text}")
