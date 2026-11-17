# This file is part of the Spring engine (GPL v2 or later), see LICENSE.html
"""Compare native and compact queues with the real BAR #8935 controller."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--engine', type=Path, required=True)
parser.add_argument('--game', type=Path)
parser.add_argument('--rapid-assets', type=Path, help='Directory containing packages/ and pool/ for an exact Rapid game')
parser.add_argument('--game-name', default='Beyond All Reason $VERSION')
parser.add_argument('--bar-repo', type=Path)
parser.add_argument('--runtime', type=Path, help='Frozen runtime overlay; otherwise read --bar-ref from --bar-repo')
parser.add_argument('--bar-ref', default='ed615ccc55126d032ba9c70cdb2e547e0a01bd51')
parser.add_argument('--maps', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--callin', choices=['UnitDeleted', 'UnitPreDelete'], required=True)
parser.add_argument('--compact', action='store_true')
parser.add_argument('--ground', action='store_true')
parser.add_argument('--fire-at-killed', action='store_true')
parser.add_argument('--scenario', choices=['active', 'pending', 'neutral', 'recycle', 'combat'], default='active')
parser.add_argument('--port', type=int, default=51321)
parser.add_argument('--frames', type=int)
args = parser.parse_args()
if not args.game and not args.rapid_assets:
    parser.error("--game or --rapid-assets is required")
if args.fire_at_killed and not args.game:
    parser.error("--fire-at-killed requires --game for modrules.lua")
if not args.runtime and not args.bar_repo:
    parser.error("--runtime or --bar-repo is required")
default_frames = (1200 if args.ground else 600) if args.scenario == 'combat' else 150
frames = args.frames if args.frames is not None else default_frames
if frames < 1:
    parser.error('--frames must be positive')
root = args.output.resolve()
root.mkdir(parents=True, exist_ok=False)
overlay = root / 'games/validation.sdd'
overlay.mkdir(parents=True)
if args.rapid_assets:
    for name in ('packages', 'pool'):
        (root / name).symlink_to((args.rapid_assets / name).resolve())
else:
    (root / 'games/game.sdd').symlink_to(args.game.resolve())
(root / 'maps').symlink_to(args.maps.resolve())
provenance = {}
runtime = ['luarules/gadgets.lua', 'luarules/gadgets/cmd_attack_targets.lua',
           'luarules/gadgets/unit_target_on_the_move.lua', 'luarules/Utilities/shared_target_list_store.lua']
if args.runtime:
    runtime = sorted(str(p.relative_to(args.runtime)) for p in args.runtime.rglob('*') if p.is_file())
for name in runtime:
    content = ((args.runtime / name).read_text() if args.runtime else
               subprocess.check_output(['git', 'show', f'{args.bar_ref}:{name}'], cwd=args.bar_repo).decode())
    provenance[name] = hashlib.sha256(content.encode()).hexdigest()
    content = content.replace('UnitPreDelete', args.callin).replace('UnitDeleted', args.callin)
    path = overlay / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
(overlay / 'modinfo.lua').write_text('return {name="Compact Lifecycle Validation",version="1",modtype=1,depend={' + json.dumps(args.game_name) + '}}\n')
(overlay / 'luaui.lua').write_text('Spring.Echo("COMPACT_UI_DISABLED")\n')
if args.fire_at_killed:
    (overlay / 'gamedata').mkdir()
    modrules = (args.game / 'gamedata/modrules.lua').read_text()
    assert 'fireAtKilled = false' in modrules
    (overlay / 'gamedata/modrules.lua').write_text(modrules.replace('fireAtKilled = false', 'fireAtKilled = true', 1))
observer = Path(__file__).with_name('compact.lua').read_text().replace('UnitDeleted', args.callin)
settings = f'local useCompact = {str(args.compact).lower()}\nlocal groundFixture = {str(args.ground).lower()}\nlocal scenario = "{args.scenario}"\nlocal lifecycleCallin = "{args.callin}"\nlocal validationEndFrame = {frames}\n'
(overlay / 'luarules/gadgets/dbg_compact_validation.lua').write_text(settings + observer)
(root / 'observer.snapshot.lua').write_text(settings + observer)
(root / 'provenance.json').write_text(json.dumps(dict(bar_ref=None if args.runtime else args.bar_ref, runtime=str(args.runtime) if args.runtime else None, original_sha256=provenance, observer_sha256=hashlib.sha256((settings + observer).encode()).hexdigest()), indent=2) + '\n')
(root / 'springsettings.cfg').write_text(f'HostPortDefault={args.port}\nNoSound=1\nWorkerThreadCount=2\nHardwareThreadCount=1\n')
map_name = 'Quicksilver Remake 1.24' if args.ground else 'Supreme Isthmus v2.1'
(root / 'startscript.txt').write_text(f'''[GAME] {{
 MapName={map_name}; GameType=Compact Lifecycle Validation 1;
 IsHost=1; HostIP=127.0.0.1; MyPlayerName=Validation; GameStartDelay=0; StartPosType=0;
 FixedRNGSeed=1; RecordDemo=0; MinSpeed=20; MaxSpeed=20;
 [MODOPTIONS] {{ deathmode=neverend; }}
 [PLAYER0] {{ Name=Validation; Team=0; }}
 [TEAM0] {{ TeamLeader=0; AllyTeam=0; }} [ALLYTEAM0] {{ }}
 [TEAM1] {{ TeamLeader=0; AllyTeam=1; }} [ALLYTEAM1] {{ }}
}}\n''')
exit_code = None
try:
    with (root / 'console.log').open('w') as log:
        result = subprocess.run([str(args.engine.resolve()), '--isolation', '--write-dir', str(root), str(root / 'startscript.txt')], cwd=root, stdout=log, stderr=subprocess.STDOUT, timeout=90)
        exit_code = result.returncode
except subprocess.TimeoutExpired:
    pass
finally:
    shutil.rmtree(root / 'games')
    (root / 'maps').unlink()
    for name in ('packages', 'pool'):
        if (root / name).is_symlink():
            (root / name).unlink()
text = (root / 'console.log').read_text(errors='replace')
for name, prefix in [('behavior', 'COMPACT_BEHAVIOR|'), ('raw', 'COMPACT_RAW|')]:
    entries = [line.split(prefix, 1)[1] for line in text.splitlines() if prefix in line]
    (root / f'{name}.json').write_text(json.dumps(entries, indent=2) + '\n')
passed = exit_code == 0 and 'COMPACT_VALIDATION_COMPLETE' in text and 'COMPACT_UI_DISABLED' in text and 'Loading widget from mod:' not in text and not any(marker in text for marker in ['LUA_ERR', 'RunCallInTraceback', 'Fatal:'])
(root / 'result.json').write_text(json.dumps(dict(passed=passed, exit=exit_code, compact=args.compact, callin=args.callin, scenario=args.scenario, ground=args.ground, fire_at_killed=args.fire_at_killed, frames=frames), indent=2) + '\n')
assert passed, root
print('Compact lifecycle fixture passed:', root)
