#!/usr/bin/env python3
"""Dump player commands (NETMSG_COMMAND / AICOMMAND) from a Spring demo, with selection sizes."""
import gzip, re, struct, sys, json

NETMSG_KEYFRAME, NETMSG_NEWFRAME, NETMSG_PLAYERNAME, NETMSG_COMMAND, NETMSG_SELECT, NETMSG_AICOMMAND, NETMSG_AICOMMAND_TRACKED = 1, 2, 6, 11, 12, 14, 76
CMDNAMES = {0:"STOP",1:"INSERT",2:"REMOVE",5:"WAIT",10:"MOVE",15:"PATROL",16:"FIGHT",20:"ATTACK",21:"AREA_ATTACK",25:"GUARD",40:"REPAIR",45:"FIRE_STATE",50:"MOVE_STATE",90:"RECLAIM",115:"REPEAT",34923:"SET_TARGET",34924:"CANCEL_TARGET"}

def main():
    path = sys.argv[1]
    cmd_filter = set(int(x) for x in sys.argv[2].split(",")) if len(sys.argv) > 2 and sys.argv[2] else None
    tmin = float(sys.argv[3]) if len(sys.argv) > 3 else 0
    tmax = float(sys.argv[4]) if len(sys.argv) > 4 else 1e9
    with gzip.open(path, "rb") as f:
        data = f.read()
    header_size = struct.unpack_from("<i", data, 20)[0]
    script_size = struct.unpack_from("<i", data, 304)[0]
    demo_size = struct.unpack_from("<i", data, 308)[0]
    script = data[header_size:header_size+script_size].decode("utf-8","replace")
    # players
    players = {}
    for m in re.finditer(r"\[player(\d+)\]\s*\{([^}]*)\}", script, re.S):
        kv = dict(re.findall(r"(\w+)=([^;]*);", m.group(2)))
        players[int(m.group(1))] = kv
    teams = {}
    for m in re.finditer(r"\[team(\d+)\]\s*\{([^}]*)\}", script, re.S):
        kv = dict(re.findall(r"(\w+)=([^;]*);", m.group(2)))
        teams[int(m.group(1))] = kv
    print("# players:")
    for p in sorted(players):
        kv = players[p]
        t = kv.get("team")
        tk = teams.get(int(t)) if t is not None and t.isdigit() else None
        print(f"#  p{p} {kv.get('name')} team={t} side={tk.get('side') if tk else '-'} ally={tk.get('allyteam') if tk else '-'} spec={kv.get('spectator')} startpos={(tk.get('startposx'),tk.get('startposz')) if tk else '-'}")
    pos = header_size + script_size
    end = pos + demo_size
    frame = -1
    sel = {}
    while pos < end:
        game_time, length = struct.unpack_from("<fI", data, pos)
        pos += 8
        pkt = data[pos:pos+length]
        pos += length
        if not pkt: continue
        m = pkt[0]
        if m == NETMSG_KEYFRAME and len(pkt) >= 5:
            frame = struct.unpack_from("<i", pkt, 1)[0]
        elif m == NETMSG_NEWFRAME:
            frame += 1
        elif m == NETMSG_SELECT and len(pkt) >= 4:
            n = (len(pkt)-4)//2
            sel[pkt[3]] = struct.unpack_from(f"<{n}h", pkt, 4)
        elif m == NETMSG_COMMAND and len(pkt) >= 17:
            p = pkt[3]
            cid, timeout = struct.unpack_from("<ii", pkt, 4)
            opts = pkt[12]
            n = struct.unpack_from("<I", pkt, 13)[0]
            params = struct.unpack_from(f"<{n}f", pkt, 17)
            if cmd_filter and cid not in cmd_filter: continue
            if not (tmin <= frame/30 <= tmax): continue
            s = sel.get(p, ())
            print(json.dumps({"t": f"{int(frame//30//60)}:{int(frame//30%60):02d}", "frame": frame, "p": p, "name": players.get(p,{}).get("name"), "cmd": CMDNAMES.get(cid, cid), "opts": opts, "params": [round(v,1) for v in params], "nsel": len(s), "sel": list(s)}))
        elif m in (NETMSG_AICOMMAND, NETMSG_AICOMMAND_TRACKED) and len(pkt) >= 19:
            p, ai, aiteam = pkt[3], pkt[4], pkt[5]
            uid = struct.unpack_from("<h", pkt, 6)[0]
            cid, timeout = struct.unpack_from("<ii", pkt, 8)
            opts = pkt[16]
            n = struct.unpack_from("<I", pkt, 17)[0]
            off = 21 + (4 if m == NETMSG_AICOMMAND_TRACKED else 0)
            params = struct.unpack_from(f"<{n}f", pkt, off)
            if cmd_filter and cid not in cmd_filter: continue
            if not (tmin <= frame/30 <= tmax): continue
            print(json.dumps({"t": f"{int(frame//30//60)}:{int(frame//30%60):02d}", "frame": frame, "p": p, "name": players.get(p,{}).get("name"), "cmd": CMDNAMES.get(cid, cid), "opts": opts, "params": [round(v,1) for v in params], "aicmd_unit": uid}))
main()
